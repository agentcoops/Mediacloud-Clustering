package MediaWords::DBI::Downloads;

# various helper functions for downloads

use strict;

use File::Path;
use HTML::Strip;
use HTTP::Request;
use IO::Uncompress::Gunzip;
use IO::Compress::Gzip;
use LWP::UserAgent;

use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config;

# cached HTML::Strip object
my $_html_stripper;

# return a ref to the content associated with the given download, or under if there is none
sub fetch_content_local
{
    my ($download) = @_;

    my $path = $download->{path};
    if ( !$download->{path} || ( $download->{state} ne "success" ) )
    {
        return undef;
    }

    #note redefine delimitor from '/' to '~'
    $path =~ s~^.*/(content/.*.gz)$~$1~;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    $data_dir = "" if ( !$data_dir );
    $path     = "" if ( !$path );
    $path     = "$data_dir/$path";

    my $content;

    if ( -f $path )
    {
        my $fh;
        if ( !( $fh = IO::Uncompress::Gunzip->new($path) ) )
        {
            return undef;
        }

        while ( my $line = $fh->getline )
        {
            $content .= $line;
        }

        $fh->close;
    }
    else
    {
        $path =~ s/\.gz$/.dl/;

        if ( !open( FILE, $path ) )
        {
            return undef;
        }

        while ( my $line = <FILE> )
        {
            $content .= $line;
        }
    }

    return \$content;
}

# fetch the content from the production server via http
sub fetch_content_remote
{
    my ($download) = @_;

    my $ua = LWP::UserAgent->new;

#    print STDERR "remote request for download from admin.mediacloud.org.\n URL: " . 'http://admin.mediacloud.org/admin/downloads/view/' . $download->{downloads_id} . "\n";

    if ( !defined( $download->{downloads_id} ) )
    {
        return \"";
    }

    my $username = MediaWords::Util::Config::get_config->{mediawords}->{fetch_remote_content_username};
    my $password = MediaWords::Util::Config::get_config->{mediawords}->{fetch_remote_content_password};
    my $url = MediaWords::Util::Config::get_config->{mediawords}->{fetch_remote_content_url};
    
    if (!$username || !$password || !$url) {
        die("mediawords:fetch_remote_content_username, _password, and _url must all be set");
    }

    if ($url !~ /\/$/) {
        $url = "$url/";
    }

    my $request = HTTP::Request->new( 'GET', $url . $download->{downloads_id} );
    $request->authorization_basic( $username, $password );

    my $response = $ua->request($request);

    if ( $response->is_success() )
    {
        my $content = $response->content();

        return \$content;
    }
    else
    {
        return \"";
    }
}

# fetch the content for the given download as a content_ref
sub fetch_content
{
    my ($download) = @_;

    if ( my $content_ref = fetch_content_local($download) )
    {
        return $content_ref;
    }

    my $fetch_remote = MediaWords::Util::Config::get_config->{mediawords}->{fetch_remote_content} || 'no';
    if ( $fetch_remote eq 'yes' )
    {
        return fetch_content_remote($download);
    }
    else
    {
        return \'';
    }
}

# fetch the content as lines in an array after running through the extractor preprocessor
sub fetch_preprocessed_content_lines
{
    my ($download) = @_;

    my $content_ref = fetch_content($download);

    if ( !$content_ref )
    {
        warn( "unable to find content: " . $download->{downloads_id} );
        return [];
    }

    my @lines = split( /[\n\r]+/, $$content_ref );

    MediaWords::Crawler::Extractor::preprocess( \@lines );

    return \@lines;
}

# run MediaWords::Crawler::Extractor against the download content and return a hash in the form of:
# { extracted_html => $html,    # a string with the extracted html
#   extracted_text => $text,    # a string with the extracted html strippped to text
#   download_lines => $lines,   # an array of the lines of original html
#   scores => $scores }         # the scores returned by Mediawords::Crawler::Extractor::score_lines
sub extract_download
{
    my ( $db, $download ) = @_;

    my $story = $db->query( "select * from stories where stories_id = ?", $download->{stories_id} )->hash;

    my $lines = fetch_preprocessed_content_lines($download);

    my $scores = MediaWords::Crawler::Extractor::score_lines( $lines, $story->{title}, $story->{description} );

    my $extracted_html = '';
    for ( my $i = 0 ; $i < @{$scores} ; $i++ )
    {
        if ( $scores->[$i]->{is_story} )
        {
            $extracted_html .= $lines->[$i];
        }
    }

    $_html_stripper ||= HTML::Strip->new;
    $_html_stripper->eof();

    return { extracted_html => $extracted_html, 
             extracted_text => $_html_stripper->parse($extracted_html),
             download_lines => $lines,
             scores => $scores };
}

# get the parent of this download
sub get_parent
{
    my ( $db, $download ) = @_;

    if ( !$download->{parent} )
    {
        return undef;
    }

    return $db->query( "select * from downloads where downloads_id = ?", $download->{parent} )->hash;
}

# store the download content in the file system
sub store_content
{
    my ( $db, $download, $content_ref ) = @_;

    my $feed = $db->query( "select * from feeds where feeds_id = ?", $download->{feeds_id} )->hash;

    my $t = DateTime->now;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    my @path = (
        'content',
        sprintf( "%06d", $feed->{media_id} ),
        sprintf( "%04d", $t->year ),
        sprintf( "%02d", $t->month ),
        sprintf( "%02d", $t->day ),
        sprintf( "%02d", $t->hour ),
        sprintf( "%02d", $t->minute )
    );
    for ( my $p = get_parent( $db, $download ) ; $p ; $p = get_parent( $db, $p ) )
    {
        push( @path, $p->{downloads_id} );
    }

    my $rel_path = join( '/', @path );
    my $abs_path = "$data_dir/$rel_path";

    mkpath($abs_path);

    my $rel_file = "$rel_path/" . $download->{downloads_id} . ".gz";
    my $abs_file = "$data_dir/$rel_file";

    #    print STDERR "file path $abs_file\n";

    if ( !( IO::Compress::Gzip::gzip $content_ref => $abs_file ) )
    {
        my $error = "Unable to gzip and store content: $IO::Compress::Gzip::GzipError";
        $db->query( "update downloads set state = ?, error_message = ? where downloads_id = ?",
            'error', $error, $download->{downloads_id} );
    }
    else
    {
        $db->query( "update downloads set state = ?, path = ? where downloads_id = ?",
            'success', $rel_file, $download->{downloads_id} );
    }
}

# store the download content in the file system
sub get_media_id
{
    my ( $db, $download ) = @_;

    my $feeds_id = $download->{feeds_id};

    $feeds_id || die $db->error;

    my $media_id = $db->query( "SELECT media_id from feeds where feeds_id = ?", $feeds_id )->hash->{media_id};

    $media_id || die "Could not get media id for feeds_id '$feeds_id " . $db->error;

    return $media_id;
}

1;
