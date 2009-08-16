package gsoc_old;

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
