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
  my $clusters = gsoc::clusterDataDB($date, $n);

  $c->stash->{json_data} = $clusters;
  $c->forward('Cluster::View::JSON');
}
1;
