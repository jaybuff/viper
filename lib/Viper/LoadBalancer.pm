package Viper::LoadBalancer;

use strict;
use warnings;

use Log::Log4perl qw(:easy);
use List::Compare;
use Net::Telnet;
use Viper::Util;
use Viper::Expect;

use base 'Viper';

sub new {
	my $proto = shift;
	my $args  = shift;

	if ( ref($args) ne "HASH" ) {
		LOGCROAK "you must pass " . __PACKAGE__ . " a hash reference to constructor";
	}

	# user name isn't required for foundry non-TACACS login (enable auth mode)
	# so we don't require it here
	foreach my $arg (qw( host_name jump_host password )) {
		exists $args->{$arg}
		  or LOGCROAK "missing required key $arg in hash ref to constructor " . __PACKAGE__;
	}

	# make sure jump_host is in dns
	eval { Viper::Util::nslookup( $args->{jump_host} ); };
	if ($@) {
		LOGCROAK "Can't resolve " . $args->{jump_host} . ".  Make sure it's a FQDN and in DNS.  Full Error: " . $@;
	}

	my $class = ref $proto || $proto;
	return bless $args, $class;
}

sub get_host_name { return shift->{host_name}; }
sub get_jump_host { return shift->{jump_host}; }
sub get_password  { return shift->{password}; }

# might be undef
sub get_user_name {
	return shift->{user_name}
	  or LOGDIE "user_name wasn't passed in to the constructor, so it's not set";
}

sub sync_vips {
	my $self = shift;

	my %wanted_vips = map { $_->get_host_name() => $_ } $self->get_data_source()->get_vips( $self->get_host_name() );

	DEBUG "getting a list of VIPs that are on the load balancer";
	my @vips_lb = map { $_->get_host_name() } $self->get_vips_from_load_balancer();

	# comparing lists of FQDNs
	my $lc = List::Compare->new( [ keys %wanted_vips ], \@vips_lb );

	my @to_add    = $lc->get_unique();
	my @to_delete = $lc->get_complement();

	# delete the ones that are in the load balancer, but not in the database
	foreach my $delete (@to_delete) {
		DEBUG "Deleting VIP $delete";
		$self->delete_vip_from_load_balancer($delete);
	}

	# add the vips that are in the database, but not on the load balancer
	foreach my $add (@to_add) {
		DEBUG "adding VIP $add";
		$self->add_vip_to_load_balancer( $wanted_vips{$add} );
	}

	# now that the database and the load balancer are in sync, get all the hosts in sync
	foreach my $vip_host ( keys %wanted_vips ) {
		DEBUG "syncing VIP members for vip $vip_host";
		$self->sync_vip_members($vip_host);
	}

	return;
}

sub sync_vip_members {
	my $self     = shift;
	my $vip_host = shift;

	my %wanted_hosts = map { $_->get_host_name() => $_ } $self->get_data_source()->get_vip_members( $vip_host, $self->get_host_name() );
	my @vip_hosts;
	if ( my $vip = $self->get_vip_from_load_balancer($vip_host) ) {
		@vip_hosts = map { $_->get_host_name() } @{ $vip->get_members() };
	}

	# comparing lists of FQDNs
	DEBUG "wanted hosts: " . join( ", ", keys %wanted_hosts );
	DEBUG "vip hosts: " . join( ", ", @vip_hosts );
	my $lc = List::Compare->new( [ keys %wanted_hosts ], \@vip_hosts );

	my @to_add    = $lc->get_unique();
	my @to_delete = $lc->get_complement();

	foreach my $delete (@to_delete) {
		DEBUG "sync_vip_members: deleting host $delete\n";
		$self->delete_member_from_vip( $vip_host, $delete );
	}

	foreach my $add (@to_add) {
		DEBUG "sync_vip_members: adding host $add\n";
		$self->add_member_to_vip( $vip_host, $wanted_hosts{$add} );
	}

	return;
}

{
	my $pid;

	sub create_ssh_tunnel {
		my $self      = shift;
		my $lb_host   = $self->get_host_name();
		my $jump_host = $self->get_jump_host();

		DEBUG "connecting to load balancer $lb_host through jump server $jump_host";

		# there can only be one ssh tunnel at a time, because there is only
		# one port.  maybe we could create multiple ones and assign them to
		# random ports, but I'm not sure how to determine if a port is in use
		if ($pid) {
			close_ssh_tunnel();
		}

		my $config           = $self->get_config();
		my $local_port       = $config->get_local_forwarded_port();
		my $ssh_key          = $config->get_ssh_private_key();
		my $jump_server_user = $config->get_jump_server_user();

		if ( Viper::Util::is_port_open($local_port) ) {
			LOGDIE "Local TCP port $local_port is still open.  Can't create ssh tunnel";
		}

		# 23 is the telnet port.  the load balancers are always listening on port 23 (telnet)
		my $cmd = "ssh -2 -i $ssh_key -N -L $local_port:$lb_host:23  -o 'StrictHostKeyChecking no' $jump_server_user\@$jump_host";

		DEBUG "create ssh tunnel with command: $cmd";
		unless ( $pid = fork ) {    # child process
			die "problem spawning program: $!\n" unless defined $pid;
			exec $cmd or die "problem executing $cmd\n";
		}

        # we'll wait upto 30 seconds for the port to be open
        my $secs_left_to_sleep = 30;
		while ( !Viper::Util::is_port_open($local_port) ) {
            if ( $secs_left_to_sleep < 0 ) { 
                LOGDIE "waited 30 seconds for ssh tunnel to be created on port $local_port.  Still nothing on that port";
            }
            $secs_left_to_sleep -= sleep 1;
        }


		return;
	}

	sub close_ssh_tunnel {
		if ($pid) {
			DEBUG "killing ssh tunnel, which has pid $pid";

			# 2 is SIGINT
			kill 2, $pid;
		}

		return;
	}

	# kill the ssh tunnel whenever this perl script exits
	END {
		close_ssh_tunnel();
	}

}

sub connect_with_expect {
	my $self = shift;

	$self->create_ssh_tunnel();

	my $port = $self->get_config()->get_local_forwarded_port();
	DEBUG "telnet localhost $port";
	my $telnet = Net::Telnet->new(
		Host => "localhost",
		Port => $port,
	);

	my $exp = Viper::Expect->exp_init($telnet);
	$exp->log_file( $self->get_host_name() );

	#$exp->exp_internal(1);

	return $exp;
}

1;

__END__

=head1 NAME

Viper::LoadBalancer - Abstract class for talking to a load balancer

=head1 DESCRIPTION

This is a base class for interfacing to a load balancer.  All subclasses that implement this 
abstract class should work the same.  See the SYNOPSIS for an example of using the foundry 
implementation

Viper::LoadBalancer extends the Viper base class.

=head1 SYNOPSIS

    use Viper::LoadBalancer::Foundry;
    use Viper::LoadBalancer::VIP;
    use Viper::LoadBalancer::VIP::Member;

    my $lb_host = 'lbf-5.pdq.yahoo.com';
    my $jump_server = 'tftp1.pdq.corp.yahoo.com';
	my $lb = Viper::LoadBalancer::Foundry->new( $lb_host, $jump_server );

    # this host name must resolve
    my $vip_host = 'pc.pers.vip.mud.yahoo.com';
    $lb->add_vip_to_load_balancer(
        Viper::LoadBalancer::VIP->new(
            {
                host_name => $vip_host,
                port      => 80,
            }
        )
    );

    # add three hosts to the vip we added above
    # all three will have the same health check and port
    my $vip_member = Viper::LoadBalancer::VIP::Member->new(
        {
            port         => 80,
            health_check => 'port http url "GET /status.html HTTP/1.0"',
        }
    );

    foreach my $member_host (
        qw(
        md1.pers.mud.yahoo.com
        md2.pers.mud.yahoo.com
        md3.pers.mud.yahoo.com
        )
      )
    {
        $vip_member->set_host_name($member_host);
        $lb->add_member_to_vip( $vip_host, $vip_member );
    }

    # delete one of the members from the VIP
    $lb->delete_member_from_vip( $vip_host, 'md2.pers.mud.yahoo.com' );

    # delete that VIP
    $lb->delete_vip_from_load_balancer( $vip_host );

    # print out all the VIPs and the members in each VIP
    foreach my $vip ( $lb->get_vips_from_load_balancer() ) { 
        print "Members in VIP " . $vip->get_host_name() . " listening on port " . $vip->get_port() . "\n";
        foreach my $member ( @{ $vip->get_members() } ) {
            print "\t$member->get_host_name() . ":" . $member->get_port() . " (health check: " . $member->get_health_check() . ")\n";
        }
        print "\n";
    }

=head1 METHODS

=over 8

=item B<new>

Constructor to create a Viper::LoadBalancer object.  Takes two arguments: load balancer 
host name, jump server 

=item B<sync_vips>

Iterates through all the VIPs and:

1.  deletes VIPs that are on the load balancer but not in the source of truth
2.  adds VIPs that are in the source of truth, but not in the load balancer
3.  call sync_vip_members for this vip

The source of truth is determined by the perl class defined in the config file 
as C<< data_source_plugin >>

=item B<sync_vip_members>

=item B<connect_with_expect>

Connect to a load balancer through a jump server.  This sets up an ssh local port forward 
to the jumo server and then spawns a telnet session with perl's Expect module and returns 
it.

Example:

    my $expect = $lb->connect_with_expect( 'lbf-5.pdq.yahoo.com', 'tftp1.pdq.corp.yahoo.com' );

=item C<< $lb->get_user_name() >>

return the user name that is to be used when authenticating with the load balancer (not the jump server).

=item C<< $lb->get_password() >>

return the password that is to be used when authenticating with the load balancer (not the jump server).

=item C<< $lb->create_ssh_tunnel() >>

Connect to the jump server via ssh using the private key that is defined in the config 
file in the ssh_private_key setting.

It will open a telnet port on localhost (defined as local_forwarded_port in the config) that
goes through the jump server to connect you to the load balancer.

Note that since this always uses the same port you can only have one tunnel created at a time.

=item C<< $lb->close_ssh_tunnel() >>

Kills the ssh process that was created using the create_ssh_tunnel method.  If there was no 
tunnel created, then it quietly returns.

=item C<< my $host_name = $lb->get_host_name() >>

Returns the host name of the load balancer that was passed in to the constructor.

=item C<< my $jump_host = $lb->get_jump_host() >>
 
Returns the jump server host name that was passed in to the constructor.

=item ABSTRACT B<add_vip_to_load_balancer>

=item ABSTRACT B<delete_vip_from_load_balancer>

=item ABSTRACT B<get_vip_from_load_balancer>

=item ABSTRACT B<get_vips_from_load_balancer>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
