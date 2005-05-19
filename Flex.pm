package Catalyst::Plugin::Session::Flex;

use strict;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;
use NEXT;
use Apache::Session::Flex;
use Digest::MD5;
use URI;
use URI::Find;

our $VERSION = '0.01';

__PACKAGE__->mk_classdata('_session');
__PACKAGE__->mk_accessors('sessionid');

=head1 NAME

Catalyst::Plugin::Session::Flex - Apache::Flex sessions for Catalyst

=head1 SYNOPSIS

use Catalyst 'Session::Flex';

MyApp->config->{session} = {
    Store => 'File',
    Lock => 'Null',
    Generate => 'MD5',
    Serialize => 'Storable',
};

=head1 DESCRIPTION

Session management using Apache::Session via Apache::Session::Flex

=head2 EXTENDED METHODS

=head3 finalize

=cut

sub finalize {
  my $c = shift;
  if ( $c->config->{session}->{rewrite} ) {
    my $redirect = $c->response->redirect;
    $c->response->redirect( $c->uri($redirect) ) if $redirect;
  }
  
  if ( my $sid = $c->sessionid ) {
    my $set = 1;
    if ( my $cookie = $c->request->cookies->{session} ) {
      $set = 0 if $cookie->value eq $sid;
    }
    $c->response->cookies->{session} = { value => $sid } if $set;
    if ( $c->config->{session}->{rewrite} ) {
      my $finder = URI::Find->new(
				  sub {
				    my ( $uri, $orig ) = @_;
				    my $base = $c->request->base;
				    return $orig unless $orig =~ /^$base/;
				    return $orig if $uri->path =~ /\/-\//;
				    return $c->uri($orig);
				  }
				 );
      $finder->find( \$c->res->{body} ) if $c->res->body;
    }
  }
  return $c->NEXT::finalize(@_);
}

=head3 prepare_action

=cut

sub prepare_action {
  my $c = shift;
  if ( $c->request->path =~ /^(.*)\/\-\/(.+)$/ ) {
    $c->request->path($1);
    $c->sessionid($2);
    $c->log->debug(qq/Found sessionid "$2" in path/) if $c->debug;
  }
  if ( my $cookie = $c->request->cookies->{session} ) {
    my $sid = $cookie->value;
    $c->sessionid($sid);
    $c->log->debug(qq/Found sessionid "$sid" in cookie/) if $c->debug;
  }
  $c->NEXT::prepare_action(@_);  
}

sub session {
  my $c = shift;
  return $c->{session} if $c->{session};
  my $sid = $c->sessionid;

  if($sid) {
    # Load the session.
    my %session;
    tie %session, 'Apache::Session::Flex', $sid, $c->config->{session};
    # Duplate the data from the store.
    
    $c->{session} = \%session;
    return $c->session;
  } 
  
  my %session;
  tie %session, 'Apache::Session::Flex', undef, $c->config->{session};
  # Load in the session id.
  $c->sessionid($session{_session_id});
  $c->log->debug(qq/Created session "$sid"/) if $c->debug;
  return $c->{session} = \%session;      
}


=head3 setup

=cut

sub setup {
  my $self = shift;
  
  # Load in the sensible defaults for session storage.
  my %defaults = (
		  Store => 'File',
		  Lock => 'Null',
		  Generate => 'MD5',
		  Serialize => 'Storable',

		  # Defaults for the defaults.
		  Directory => '/tmp/session',
		  LockDirectory => '/var/lock/sessions',
		 );

  while(my ($k, $v) = each %defaults) {
    $self->config->{session}->{$k} ||= $v;
  }
  
  return $self->NEXT::setup(@_);
}

=head2 METHODS

=head3 session

=head3 uri

Extends an uri with session id if needed.

    my $uri = $c->uri('http://localhost/foo');

=cut

sub uri {
    my ( $c, $uri ) = @_;
    if ( my $sid = $c->sessionid ) {
        $uri = URI->new($uri);
        my $path = $uri->path;
        $path .= '/' unless $path =~ /\/$/;
        $uri->path( $path . "-/$sid" );
        return $uri->as_string;
    }
    return $uri;
}


=head2 CONFIG OPTIONS

All of the options are inheritied from L<Apache::Session::Flex> and
various L<Apache::Session> modules such as L<Apache::Session::File>.

=head3 rewrite

To enable automatic storing of sessions in the url set this to a true value.

=head1 SEE ALSO

L<Catalyst> L<Apache::Session> L<Apache::Session::Flex>

=head1 AUTHOR

Rusty Conover C<rconover@infogears.com>

Based off of L<Catalyst::Plugin::Session::FastMmap> by:

Sebastian Riedel, C<sri@cpan.org>
Marcus Ramberg C<mramberg@cpan.org>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
