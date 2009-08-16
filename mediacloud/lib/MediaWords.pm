package MediaWords;

use strict;
use warnings;

use Catalyst::Runtime '5.70';

use DBIx::Simple::MediaWords;
use MediaWords::Util::Config;
use URI;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
  -Debug
  ConfigLoader
  ConfigDefaults
  Static::Simple
  Session
  Session::Store::FastMmap
  Session::State::Cookie
  Unicode
  StackTrace
  /;

our $VERSION = '0.01';

use HTML::FormFu;

# Configure the application.
#
# Note that settings in mediawords.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

my $config = __PACKAGE__->config( -name => 'MediaWords' );

# Start the application
__PACKAGE__->setup;

sub uri_for
{
    my ( $self, $path, $args ) = @_;

    if ( !$self->config->{mediawords}->{base_url} )
    {
        shift(@_);
        return $self->SUPER::uri_for(@_);
    }

    my $uri = URI->new( $self->config->{mediawords}->{base_url} . $path );

    if ($args)
    {
        $uri->query_form($args);
    }

    return $uri->as_string();
}

# shortcut to dbis model
sub dbis
{

    return $_[0]->model('DBIS')->dbis;
}

=head1 NAME

MediaWords - Catalyst based application

=head1 SYNOPSIS

    script/mediawords_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<MediaWords::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
