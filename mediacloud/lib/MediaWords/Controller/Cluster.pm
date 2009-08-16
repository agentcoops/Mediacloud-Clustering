package MediaWords::Controller::Cluster;

BEGIN {
    use FindBin;
    use lib "/Users/francisc/Coding/perl/mediacloud/lib";
}
use JSON;
use strict;
use warnings;
use Data::Dumper;
use MediaWords::DB;
use Statistics::Cluto;
use DBIx::Simple::MediaWords;
use UNIVERSAL 'isa';

use base 'Catalyst::Controller';

#<- Code for caching sparse matrix to speed up creating clusters. ->#
# At present unfinished and unintegrated into the main clustering
# sub-routine.  

##
# Check if the cache directory exists or else make it.
sub checkForCacheOrMake {
  unless (-e "matrix_cache") {
      mkdir "matrix_cache" or die "Could not make cache."
  };
}

##
# Output a cluster file for cluto.
sub writeCluto {
  my $date = $_[1];
  my @matrix_data = @{ $_[0] };

  my ($ncols, $nrows, $nonzero) = @matrix_data[0,1,2];
  my @rowvals = @{ $matrix_data[3] };
  my @rowlabels = @{ $matrix_data[4] };

  checkForCacheOrMake;
  open my $out, '>>', "matrix_cache/$date";
  print {$out} "$nrows $ncols $nonzero\n";
  for my $row (@rowvals) {
    print {$out} (join(" ", @{ $row })) . "\n";
  }

  close $out;
}

## TO FINISH 
# Load a txt file containing a cluto formatted sparse matrix.
sub readCluto {
  my $file_loc = $_[0];
  my @sparse_matrix;
  
  open my $in, '<', $file_loc;
  my $line1 = <$in>;
  chomp($line1);
  my ($nrows, $ncols, $nonzero) = split(" ", $line1);

  while( my $line = <$in> ) {
    chomp($line);
    my @row_vals = split(" ", $line);
    
    push @sparse_matrix, \@row_vals;
  }

  return ($ncols, $nrows, $nonzero, )
}


#<- Misc Helper Subroutines. ->#

##
# Combine two lists into a list of lists each such element containing a pair of elts from
# the input lists.  For example, zip([1,2,3],[4,5,6]) = [[1,4],[2,5],[3,6]].
sub zip {
  my ($arr1, $arr2) = @_[0,1];
  map {[$$arr1[$_], $$arr2[$_]]} (0 .. (scalar(@$arr1)-1));
}

##
# Get the five elements of input array starting at index.
# get5([1,2,3,4,5,6], 0) => [1,2,3,4,5]
sub getFiveFrom { 
  @{$_[0]}[($_[1]*5) .. (($_[1]+1)*5-1)] 
}


#<- DBI Helper Subroutines.  ->#

##
# Store a cluster in the mediacloud database.
sub storeClusters {
  my ($db, $start_date, $end_date, 
      $num_clusters, $description, $tag, $clusters) = @_;

  my $stored_cluster = 
    $db->create(
      'media_cluster_runs',
      {
       start_date => $start_date,
       end_date => $end_date,
       num_clusters => $num_clusters,
       tags_id => undef,
       description => $description
      }
    );

  my $cluster_run_id = 
    $db->last_insert_id( undef, undef, 'media_cluster_runs', undef );

    
}

sub getClustersOrCreate {

}


#<- Main Clustering Subroutines. ->#

##
# Load the top $count terms for a given data from MC db, also  
# puts the total count in hash.  Ignores stop words.
sub loadTermsDB {
  my ($db, $count, $date) = @_[0,1,2];
  my %data;
  my $index = 1;
  
  my $stems = 
    $db->query("SELECT stem, SUM(stem_count) AS ssc 
                FROM weekly_media_words 
                WHERE publish_week = '$date' and not is_stop_stem('long', stem)
                GROUP BY stem 
                ORDER BY ssc DESC");
  for my $i (0 .. $count) {
    my %stem_hash = %{ $stems->hash() };
    my ($stem, $total) = @stem_hash{'stem', 'ssc'};
    
    $data{$stem} = [$index, $total];
    $index++;
  }

  return \%data;
}

##
# Make a mapping from indexes to terms. Accepts a termhash.
sub reverseTermIndex {
  my %term_hash = %{ $_[0] };
  my %index_to_term;
  my $last;

  for (%term_hash) {
    if (isa($_, "ARRAY")) {
      $index_to_term{@{$_}[0]} = $last;
    } else {
      $last = $_;
    }
  }

  return \%index_to_term;
}

##
# Make a lookup of all media outlets.
sub makeLookupDB {
  my %lookup;
  my $db = $_[0];
  my $medias = $db->query("SELECT media_id, name
                           FROM media");
  
  while(my $media_ref = $medias->hash()) {
    my %media = %{ $media_ref };
    my $media_id = $media{media_id};
    my $name = $media{name};

    $lookup{$media_id} = $name;
  }

  return \%lookup;
}

##
# Load termhash directly from the DB.
sub termHashDateDB {
    my ($db, $date) = @_[0,1];
    my %data;
    my %term_index = %{ loadTermsDB($db, 20000, $date) };

    my $media_datas = 
      $db->query("SELECT media_id, stem, stem_count
                  FROM weekly_media_words
                  WHERE publish_week = CAST('$date' AS timestamp without time zone)
                  ORDER BY stem_count DESC");

    while(my $media_data = $media_datas->hash()) {
      my %media_data = %{ $media_data };
      my $media_id = $media_data{"media_id"};
      my $stem = $media_data{"stem"};

      eval {
        my $index = (@{ $term_index{$stem} })[0];
        push @{ $data{$media_id} }, $index; 
      };
    }

    return (\%data, reverseTermIndex(\%term_index));
}

##
# Makes a sparse-matrix representation of all the media vectors for a 
# given month. Accepts a termdate hash.
sub makeSparseMatrix {
  my %date_hash = %{ $_[0] };
  my $ncols = 150000;
  my $nrows = scalar(keys %date_hash);
  
  my @rowlabels;
  my @rowvals;
  my $nonzero = 0;
  
  open my $media_out, ">>", "media.out";
  my @sorted_media = sort(keys %date_hash);
  for my $media (@sorted_media) {
    print {$media_out} "$media\n";
    my @terms = sort(@{ $date_hash{$media} });
    my @row;
    
    for my $term (@terms) {
      if ($term < $ncols) {
        push @row, $term, 1; 
        $nonzero++;
      }
    }

    push @rowlabels, $media;
    push @rowvals, \@row;
  }

  return ($ncols, $nrows, $nonzero, \@rowvals, \@rowlabels);
}

##
# Make a sparse mkatrix of term occurrences 
sub makeSparseMatrixDB {
  my ($db, $date) = @_[0,1];
  my ($date_hash, $index_map) =  termHashDateDB($db, $date);

  my ($ncols, $nrows, $nonzero, 
      $rowvals, $rowlabels) = makeSparseMatrix($date_hash);
  return ($ncols, $nrows, $nonzero, $rowvals, $rowlabels, $index_map);
}

##
# Return connection to MediaWords database.
sub connectDB {
  my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);
  return $db;
}

##
# Accepts a recently clustered cluto object, the number of columns and a term-index 
# lookup.  Returns a hash mapping cluster numbers to pair of lists of feature, 
# weight pairs.  The first such list contains the most important terms held by inhabitants
# of a cluster, the other list contains the most important terms that differentiate this
# cluster from any other.
sub getClusterFeatures {
  my($c, $ncols, $index_lookup) = @_[0,1,2];
  my($internalids, $internalwgts, 
     $externalids, $externalwgts) = $c->V_GetClusterFeatures;
  my %data;

  for my $cluster (0 .. ($ncols-1)) {
    my @raw_int_features = getFiveFrom($internalids, $cluster);
    my @int_features = map {$index_lookup->{$_}} @raw_int_features;
    my @int_weights = getFiveFrom($internalwgts, $cluster);
    my @int_feature_weights = zip(\@int_features, \@int_weights);

    my @raw_ext_features = getFiveFrom($externalids, $cluster);
    my @ext_features = map {$index_lookup->{$_}} @raw_ext_features;
    my @ext_weights = getFiveFrom($externalwgts, $cluster);
    my @ext_feature_weights = zip(\@ext_features, \@ext_weights);

    $data{$cluster} = [\@int_feature_weights, \@ext_feature_weights];
  }

  \%data;
}

##
# Take cluster output and make it properly readable.
# Accepts a mediacloud db, a map from cluster ids to lists of feature, weight pairs,
# a list of clusters, and a list with each index containing the cluster that row belongs
# to.  Outputs map from cluster ids to pair of the key features for that cluster and 
# the names of the media outlets occurring therein.  
sub prettifyClusters {
  my($db, $cluster_features) = @_[0,3];
  my @clusters = @{ $_[1] };
  my @rownames = @{ $_[2] };
  my %lookup = %{ makeLookupDB($db) };
  my %cluster_results;    
  
  for my $row (0 .. scalar(@rownames)-1) {
    my $cluster = $clusters[$row];
    my $media_id = $rownames[$row];
    my $media_name = $lookup{ $media_id };
    if (!$cluster_results{$cluster}) {
      my $key_features = $cluster_features->{$cluster};
      push @{ $cluster_results{$cluster} }, $key_features;
      push @{ $cluster_results{$cluster} }, [];
    }
    
    push @{ $cluster_results{$cluster}[1] }, $media_name;
  }

  return \%cluster_results;
}

## TODO: Make db integration work. 
# Return a map of cluster ids to arrays of media names.
# Accepts date to cluster and how many clusters you want.
sub clusterDataDB {
  my ($date, $nclusters) = @_[0, 1];
  my $db = connectDB;
  my @cluster_data;

  # Unfinished cache code commented out...
  #if (-e "matrix_cache/$date") {
  #  @cluster_data = loadCluto("matrix_cache/$date");
  #} else { 
  @cluster_data = makeSparseMatrixDB($db, $date);
  #  writeCluto(\@cluster_data, $date);
  #};

  my ($ncols, $nrows, $nonzero, 
      $rowvals, $rowlabels, $index_map) = @cluster_data[0 .. 5];
  my $c = new Statistics::Cluto;

  $c->set_sparse_matrix($nrows, $ncols, $rowvals);
  $c->set_options({
                   rowlabels => $rowlabels,
                   nclusters => $nclusters
                  });

  my $clusters = $c->VP_ClusterDirect;
  my $cluster_features = getClusterFeatures($c, $ncols, $index_map);
  return prettifyClusters($db, $clusters, $rowlabels, $cluster_features);
}


##
# Action for creating a new cluster.
sub home: Local {
  my ($self, $c) = @_;

  # make cluster form.
  my $form = HTML::FormFu->new(
    {
      load_config_file => $c->path_to() . '/root/forms/cluster.yml',
      method           => 'GET',
      action           => ''
    }
  );

  $form->process( $c->request );
  
  # form parameters
  my $params;

  my $type = $c->request->param('type') || 'term';
  my $from = $c->request->param('from');
  my $to = $c->request->param('to');
  my $description = $c->request->param('description');
  my $clusters = $c->request->param('clusters'); 
  my $tag = $c->request->param('source_tag_name');

  my $cluster_results = clusterDataDB($from, $clusters);

  $c->stash->{form} = $form;
  $c->stash->{clusters} = $cluster_results;
  $c->stash->{template} = 'cluster/show.tt2';
}

=head1 AUTHOR

Cooper Francis

=head1 LICENSE

AGPL

=cut

1;
