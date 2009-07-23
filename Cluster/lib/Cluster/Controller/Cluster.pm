package Cluster::Controller::Cluster;
use parent 'Catalyst::Controller';
use JSON;
use gsoc;

sub date : Chained : CaptureArgs(1) {
  my ( $self, $c, $date ) = @_;
  $c->stash->{date} = $date;
}

sub n : Chained('date') : Args(1) {
  my ($self, $c, $n ) = @_;
  my $date = $c->stash->{date};
  my %cluster = %{ gsoc::clusterDataDB($date, $n) };

  $c->stash->{json_data} = \%cluster;
  $c->forward('Cluster::View::JSON');
}
1;
