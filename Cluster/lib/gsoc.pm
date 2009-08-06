package gsoc;
our $version = ".01";

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
use List::MoreUtils 'mesh';
use UNIVERSAL 'isa';

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
# Load a cluto sparse matrix format.
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

##
# Load the top $count terms for a given data from MC db, also  
# puts the total count in hash.
sub loadTermsDB {
  my ($db, $count, $date) = @_[0,1,2];
  my %data;
  my $index = 1;
  
  my $stems = 
    $db->query("SELECT stem, SUM(stem_count) AS ssc 
                FROM weekly_media_words 
                WHERE publish_week = '$date'
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

## TO FINISH
# Get the summary of the clustering results having been passed a reference
# to a cluto object.
sub clusterSum {
  my $c = $_[0];
  my @results = $c->V_GetClusterSummaries;
  my $r_nsum = $results[0];
  my @r_spid = @{ $results[1] };
  my @r_swgt = @{ $results[2] };
  my @r_sumptr = @{ $results[3] };
  my @r_sumind = @{ $results[4] };  
}

##
# Zip together two lists.
sub zip {
  my ($arr1, $arr2) = @_[0,1];
  map {[$$arr1[$_], $$arr2[$_]]} (0 .. (scalar(@$arr1)-1));
}

##
# Get the five elements of input array starting at index.
# get5([1,2,3,4,5,6], 0) => [1,2,3,4,5]
sub getFiveFrom { @{$_[0]}[($_[1]*5) .. (($_[1]+1)*5-1)] };

##
# Return a hash mapping cluster numbers to lists of feature, weight pairs.
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

## TODO: Make caching work. 
# Return a map of cluster ids to arrays of media names.
# Accepts date to cluster and how many clusters you want.
sub clusterDataDB {
  my ($date, $nclusters) = @_[0, 1];
  my $db = connectDB;
  my @cluster_data;

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


#<---- MISC UTILITIES ---->#

###
# Given a term-vector csv file and a list of media ids to track 
# produces txt file containing just the vectors corresponding to 
# the given ids.
sub filterById {
    my $filename = $_[1];
    my @ids = @_[2..scalar(@_)-1];
    
    my %is_id;
    for (@ids) {$is_id{$_} = 1};

    open my $in, '<', $filename;
    open my $out, '>>', $filename . ".subset";

    while (my $line = <$in>) {
        chomp($line);
        my ($mw_id, $media_id, $term, 
            $stem, $stem_count, $date) = split(",", $line);
        
        if ($is_id{$media_id}) { print {$out} $line, "\n" };            
    }
}

##
# Load the term list up to a specific point.
# Termlist of form index,term,totalcount
sub loadTerms {
  my ($filename, $count) = @_[0,1];
  my %data;

  open my $in, '<', $filename;
  for my $i (0 .. $count) {
    my $line = <$in>;
    chomp($line);
    
    my($index, $term, $count) = (split(/,/, $line));
    $data{$term} = [int($index)+1, $count];
  }

  close $in;
  return \%data;
}


#<---- METHODS FOR USING CLUTO FROM COMMAND LINE ---->#

###
# Accepts the location of a mediacloud term-vector csv file
# and loads it into memory as hash of hashes of arrays.
sub termHash {
    my $filename = $_[0];
    my %data;
    my %term_hash = %{ loadTerms("sortedterms.csv", 195351) };

    open my $in, '<', $filename;

    while (my $line = <$in>) {
      chomp($line);
      my($media_id, $term, $date) = (split(/,/, $line))[1,3,5];
      $date = (split(" ", $date))[0];

      my $val = (@{ $term_hash{$term} })[0];
      push @{ $data{$date}{$media_id} }, $val;
    }  

    close $in;
    return \%data;
}

###
# Just make the termhash for a particular date.
sub termHashDate {
  my($filename, $date) = @_[0,1];
  my %termhash = %{ termHash($filename) };
  
  my %good = %{ $termhash{$date} }; 

  undef %termhash;
  return \%good;
}

sub makeSparseMatrixFile {
  my ($filename, $date) = @_[0,1];
  my %date_hash = %{ termHashDate($filename, $date) };
  
  my ($ncols, $nrows, $nonzero, 
      $rowvals, $rowlabels) = makeSparseMatrix(\%date_hash); 
  return ($ncols, $nrows, $nonzero, $rowvals, $rowlabels);
}

##
# Output row file for cluto.
sub writeRows {
  my ($filename1, $filename2) = @_[0,1];

  open my $termfile, '<', $filename1;
  my $line = <$termfile>;
  my @terms = split(/,/, $line);
  my %is_term;
  for (@terms) { $is_term{$_} = 1 };
  close $termfile;

  open my $in, '<', $filename2;
  open my $out, '>>', "rows.cluto";

  while (my $line = <$in>) {
    chomp($line);
    my ($index, $url, $medianame) = split(/,/, $line);
    if ($is_term{$index}) {
      chomp($medianame);
      if ($medianame eq '"') {
        print {$out} "$url\n";
      } else {
        print {$out} "$medianame\n";
      }
    }
  }

  close $in;
  close $out;
}

##
# Output column file for cluto.
sub writeColumns {
  my ($count, $filename) = @_[0,1];
  open my $in, "<", $filename;
  open my $out, ">>", "mc.clabels";

  for my $i (0 .. $count) {
    my $line = <$in>;
    my $term = (split(/,/, $line))[1];
    
    print {$out} "$term\n";
  }

  close $in;
  close $out;
}

##
# Make a file containing the media numbers properly clustered together into the
# clusters that they form.  
sub goodClutoOut {
  my ($filename1, $filename2) = @_[0,1];
  my %data;

  open my $media_used, "<", $filename1;
  open my $clusters, "<", $filename2;

  while (my $line_m = <$media_used>) {
    my $line_c = <$clusters>;
    
    chomp($line_m);
    chomp($line_c);

    push @{ $data{$line_c} }, $line_m; 
  }

  open my $out, ">>", "media_cluster.combo";
  for (sort {$a <=> $b} (keys %data)) {
    print {$out} "$_ ". join(",", @{ $data{$_} }) ."\n"
  };

  return \%data;
}

##
# Make a look-up of the media outlets appearing in a cluster.
sub makeLookup {
  my $filename = $_[0];
  my %data;
  open my $in, "<", $filename;

  while (my $line = <$in>) {
    chomp($line);
    print "$line\n";
    my @splits = split(/,/, $line);
    my ($id, $url) = @splits[0,1];
    my $name = join(",", @splits[2 .. scalar(@splits)-1]);
    if ($name eq '"') {
      $name = $url
    } 

    $data{$id} = $name;
  }

  return \%data;
}

##
# Takes output from goodClutoOut and replace all media ids with the acutal 
# name of that media outlet.
sub humanGoodOut {
  my ($media_file, $cluto_file) = @_[0,1];
  my %lookup = %{ makeLookup($media_file) };
  open my $cluto, "<", $cluto_file;
  open my $out, ">>", "$cluto_file.forhumans";
  
  while (my $line = <$cluto>) {
    chomp($line);
    my ($cluster, $media_string) = split(/ /, $line);
    my @medias = split(/,/, $media_string);
    my @names;

    for my $media (@medias) {
      push @names, $lookup{$media};
    }

    print {$out} "\n$cluster: ". join("\n", @names) ."\n";
  }

  close $cluto;
  close $out;
}
