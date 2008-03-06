package Apache2::AuthCASSimple;

use strict;
use Apache2::Const qw( OK AUTH_REQUIRED DECLINED REDIRECT SERVER_ERROR M_GET);
use Apache2::RequestUtil ();
use Apache2::RequestRec ();
use Apache2::Log;
use Apache::Session::Wrapper;
use Authen::CAS::Client;
#use Apache2::Cookie;
use Apache2::Connection;
use vars qw($VERSION);

$VERSION = '0.0.2';


#
# handler()
#
# Called by apache/mod_perl
#
sub handler ($) {
  my $r = shift;
  my $log = $r->log();


  # does it need to do something ?
  #return DECLINED unless($r->ap_auth_type() eq __PACKAGE__);

  $log->info(__PACKAGE__."-".$r->ap_auth_type()."-: Entering into authentification process.:".$r->uri() ."--".$r->args());
  $log->info(__PACKAGE__."---".$r->connection->remote_ip()."--: Entering into authentification process.:".$r->uri() ."--".$r->args());

  # Get module config (Apache Perl SetVAR values)
  my $cas_session_timeout = $r->dir_config('CASSessionTimeout') || 60;
  my $cas_ssl = $r->dir_config('CASServerNoSSL')?0:1;
  my $cas_name = $r->dir_config('CASServerName') || 'my.casserver.com';
  my $cas_port = $r->dir_config('CASServerPort') ? $r->dir_config('CASServerPort') : 443 ;
  $cas_port = '' if ( $cas_port == 443 && $cas_ssl );
  my $cas_path = $r->dir_config('CASServerPath') || '/' ;
  my $mod_proxy = $r->dir_config('ModProxy');

  # Check for internal session
  my $user;
  if($cas_session_timeout >= 0 && ($user = _get_user_from_session($r))) {
    $log->info(__PACKAGE__.": Session found for user $user.");
    $r->user($user);
    return OK;
  }
  elsif($cas_session_timeout >= 0) {
    $log->info(__PACKAGE__.": No session found.");
  }
  else {
    $log->info(__PACKAGE__.": Session disabled.");
  }

  # instance CAS object
  my ($cas, %options);
  $options{casUrl} = ($cas_ssl ? 'https://' : 'http://').$cas_name.':'.$cas_port.$cas_path;
 # $options{CAFile} = $cfg->{_ca_file} if ($cfg->{_cas_ssl});

  unless($cas = Authen::CAS::Client->new($options{casUrl}, fatal => 1)) {
    $log->error(__PACKAGE__.": Unable to create CAS instance.");
    return SERVER_ERROR;
  }

  my $requested_url = _get_requested_url($r,$mod_proxy);
  my $login_url = $cas->login_url().$requested_url;

  # redirect to CAS server unless ticket parameter
  my %args = map { split '=', $_ }  split '&', $r->args();
  my $ticket = $args{'ticket'};

  unless ($ticket) {
    $log->info(__PACKAGE__.": No ticket, client redirected to CAS server.");
    $r->headers_out->add("Location" => $login_url);
    return REDIRECT;
  }


  # Validate the ticket we received
  if ($ticket=~/^PT/) {
      my $r = $cas->proxy_validate( $requested_url, $ticket );
        if( $r->is_success() ) {
            $user=$r->user();
            $log->warn(__PACKAGE__.": Validate PT on CAS Proxy server. ".join ",", $r->proxies());
        };
  }
  else {
      $log->warn(__PACKAGE__.": Validate ST $requested_url, $ticket on CAS Proxy server ");
      my $r = $cas->service_validate( $requested_url, $ticket );
      if ( $r->is_success() ) {
        $user = $r->user();
      }
  }

  unless ($user) {
    $log->warn(__PACKAGE__.": Unable to validate ticket ".$ticket." on CAS server.");
    $r->err_headers_out->add("Location" => $login_url);
    return REDIRECT;
    #return FORBIDDEN;
  }

  $log->info(__PACKAGE__.": Ticket ".$ticket." succesfully validated.");

  if ( $user ) {
   $r->user($user);

   $log->info(__PACKAGE__.": New session ".$r->uri() ."--".$r->args());

   # if we are there (and timeout is set), we can create session data and cookie
   _remove_ticket($r);
   _create_user_session($r) if($cas_session_timeout >= 0);
   $r->err_headers_out->add("Location" => $r->uri . ($r->args ? '?' . $r->args : '') );

   # if session, redirect remove ticket in url
   return ($cas_session_timeout >= 0)?REDIRECT:OK;
  }

  return DECLINED;

}

#
# _get_requested_url()
#
# Return the URL requested by client (with args)
#
sub _get_requested_url ($$) {
  my $r = shift;
  my $mod_proxy = shift;

  my $port = $r->get_server_port();
  my $is_https = $r->subprocess_env('https') ? 1 : 0;

  my $url = $is_https ? 'https://' : 'http://';
  $url .= $r->hostname();
  $url .= ':'.$port if (!$mod_proxy && ( ($is_https && $port != 443) || (!$is_https && $port != 80) ));
  $url .= $r->uri()._get_query_string($r);

  return $url;
}

#
# _get_query_string()
#
# Return the query string
#
sub _get_query_string ($) {
  my $r = shift;

  _post_to_get($r) if ($r->method eq 'POST');

  my %args = map { split '=', $_ }  split '&', $r->args();
  my @qs = ();

  foreach (sort {$a cmp $b} keys(%args)) {
    next if ($_ eq 'ticket');
    push(@qs, $_."=".$args{$_});
  }

  return $#qs != -1 ? "?".join("\&", @qs) : "";
}

#
# _post_to_get()
#
# Convert POST data to GET
#
sub _post_to_get ($) {
  my $r = shift;

  my $content = $r->content;
  $r->log()->info($content);
  $r->method("GET");
  $r->method_number(M_GET);
  $r->headers_in->unset("Content-length");
  $r->args($content);
}

#
# _remove_ticket
#
# Remove ticket from query string arguments
#
sub _remove_ticket ($) {
  my $r = shift;

  my %args = map { split '=', $_ }  split '&', $r->args();
  my @qs = ();

  foreach (sort {$a cmp $b} keys(%args)) {
    next if ($_ eq 'ticket');
    push(@qs, $_."=".$args{$_});
  }

  $r->args(join("\&", @qs));
}

#
# _get_user_from_session()
#
# Retrieve username if a session exist ans is correctly filled
#
sub _get_user_from_session ($) {
  my $r = shift;
  my $s;

  my $mod_proxy = $r->dir_config('ModProxy');
  my $cas_session_dir = $r->dir_config('CASSessionDirectory') || '/tmp';
  my $cas_cookie_path = $r->dir_config('CASFixDirectory') || '/';
  my $cas_session_timeout = $r->dir_config('CASSessionTimeout') || 60;

  $r->log()->info(__PACKAGE__.": Checking session.");

    eval { $s = Apache::Session::Wrapper->new(
        class  => 'File',
        directory => $cas_session_dir,
        lock_directory  => $cas_session_dir,
        use_cookie => 1,
        cookie_secure => $r->subprocess_env('https') ? 1 : 0,
        cookie_resend => 1,
        cookie_expires => 'session',
        cookie_path => $cas_cookie_path
    ); };


    return "" unless(defined $s);


    if ($cas_session_timeout && $s->session->{'time'} + $cas_session_timeout < time) {
        $r->log()->warn(__PACKAGE__.": Session TimeOut !");
        $s->delete_session();
        return "";
    };

  my $ip = ($mod_proxy)?$r->headers_in->{'X-Forwarded-For'}:$r->connection->remote_ip();


  if($s->session->{'CASIP'} ne $ip) {
    $r->log()->warn(__PACKAGE__.": Remote IP Address changed along requests !");
    $s->delete_session();
    return "";
  }
  elsif(my $user = $s->session->{'CASUser'}) {
    return $user;
  }
  else {
    $r->log()->warn(__PACKAGE__.": Session found, but no data inside it.");
    $s->delete_session();
    return "";
  }
}

#
# _create_user_session()
#
# Create a user session and send cookie
#
sub _create_user_session ($) {
  my $r = shift;

  my $mod_proxy = $r->dir_config('ModProxy');
  my $cas_session_dir = $r->dir_config('CASSessionDirectory') || '/tmp';
  my $cas_cookie_path = $r->dir_config('CASFixDirectory') || '/';

  $r->log()->info(__PACKAGE__.": Creating session");

  my $s = Apache::Session::Wrapper->new(
        class  => 'File',
        directory => $cas_session_dir,
        lock_directory  => $cas_session_dir,
        use_cookie => 1,
        cookie_secure => $r->subprocess_env('https') ? 1 : 0,
        cookie_resend => 1,
        cookie_expires => 'session',
        cookie_path => $cas_cookie_path
        );

  unless ($s) {
    $r->log()->warn(__PACKAGE__.": Unable to create session for ".$r->connection->user().".");
    return;
  }

  $s->session->{'CASUser'} = $r->user();
  my $ip = ($mod_proxy)?$r->headers_in->{'X-Forwarded-For'}:$r->connection->remote_ip();
  $s->session->{'CASIP'} = $ip;
  $s->session->{'time'} = time();

};


1;

__END__

=head1 NAME

Apache2::AuthCASSimple - Apache2 module to authentificate trough a CAS server

=head1 DESCRIPTION

Apache2::AuthCASSimple is an authentication module for Apache2/mod_perl2. It allow you to authentificate users trough a Yale CAS server. It means you don't need to give login/password if you've already be authentificate by the CAS server, only tickets are exchanged between Web client, Apache2 server and CAS server. If you not're authentificate yet, you'll be redirect on the CAS server login form.

This module allow the use of simple text files for sessions.

=head1 SYNOPSIS


  <Location /protected>
    AuthType Apache2::AuthCASSimple
    PerlAuthenHandler Apache2::AuthCASSimple

    PerlSetVar CASServerName my.casserver.com
    PerlSetVar CASServerPath /
    # PerlSetVar CASServerPort 443
    # PerlSetVar CASServerNoSSL 1
    PerlSetVar CASSessionTimeout 60
    PerlSetVar CASSessionDirectory /tmp
    # PerlSetVar CASFixDirectory /
    # PerlSetVar ModProxy 1

    require valid-user
  </Location>

or 

  order deny,allow
  deny from all

  require user xxx yyyy

  satisfy any


=head1 CONFIGURATION

=over 4

=item CASServerName

Name of the CAS server. It can be a numeric IP address.

=item CASServerPort

Port of the CAS server. Default is 443.

=item CASServerPath

Path (URI) of the CAS server. Default is "/cas".

=item CASServerNoSSL

Disable SSL transaction wih CAS server (HTTPS). Default is off.

=item CASCaFile

CAS server public key. This file is used to allow secure connection
between the webserver using Apache2::AuthCASSimple and the CAS server.

DEPRECATED : L<Authen::CAS::Client> use L<LWP::UserAgent> to make https requests

=item CASSessionTimeout

Timeout (in second) for session create by Apache2::AuthCASSimple (to avoid CAS server overloading). Default is 60.

-1 means disable.

0 mean infinite (until the user close browser).

=item CASSessionDirectory

Directory where session data are stored. Default is /tmp.

=item CASFixDirectory

Force the path of the session cookie for same policy in all subdirectories else current directory is used.

=item ModProxy

Apache2 mod_perl2 don't be use with mod_proxy. Default is off.

=back

=head1 VERSION

This documentation describes Apache2::AuthCASSimple version 0.0.1

=head1 BUGS AND TROUBLESHOOTING

=over 4

=item *
Old expired sessions files must be deleted with an external provided script : C<delete_session_data.pl>

=item *
L<Apache::Session::Wrapper> certainly need L<Apache2::Cookie>

=item *
C<$r> must be global for sessions with L<Apache::Session::Wrapper>, add 

  PerlOptions +GlobalRequest

in your virtualhost conf

=item *
Apreq module must be enable in debian

  LoadModule apreq_module /usr/lib/apache2/modules/mod_apreq2.so

=back

Please submit any bug reports to agostini@univ-metz.fr.

=head1 NOTES

Requires C<mod_perl 2> version 2.02 or later
Requires L<Authen::CAS::Client>
Requires L<Apache::Session::Wrapper> 

=head1 AUTHOR

    Yves Agostini
    CPAN ID: YVESAGO
    Univ Metz
    agostini@univ-metz.fr
    http://www.crium.univ-metz.fr

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

