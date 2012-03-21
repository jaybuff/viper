package Viper::LoadBalancer::Foundry;

use strict;
use warnings;

use base 'Viper::LoadBalancer';
use Carp;

use Log::Log4perl qw(:easy);
use Viper::Util;
use Viper::LoadBalancer::VIP;
use Viper::LoadBalancer::VIP::Member;
use Expect;

sub get_vip_from_load_balancer {
	my $self     = shift;
	my $vip_host = shift;

	my $config = $self->get_current_config();

	return $config->{vips}->{$vip_host};
}

# return an array of Viper::LoadBalancer::VIP objects that are on this loadbalancer
sub get_vips_from_load_balancer {
	my $self = shift;

	my $config = $self->get_current_config();

	return map { $config->{vips}->{$_} } keys %{ $config->{vips} };
}

sub enter_config_mode {
	my $self = shift;
	$self->run_command(
		{
			command       => "configure terminal",
			success_regex => qr/\(config\)/,
		}
	);

	return;
}

sub exit_config_mode {
	my $self = shift;
	$self->run_command("end");

	return;
}

# given a FQDN of a vip, delete it then call delete_real_servers_not_in_a_vip()
# to clean up any orphaned real servers.
sub delete_vip_from_load_balancer {
	my $self     = shift;
	my $vip_host = shift;

	DEBUG "deleting vip host $vip_host and all it's real servers from load balancer";

	my $vip_name = $self->host_to_vip_name($vip_host);
	$self->no_server_virtual($vip_name);
	$self->delete_real_servers_not_in_a_vip();

	return;

}

sub no_server_virtual {
	my $self     = shift;
	my $vip_name = shift;

	$self->enter_config_mode();
	$self->run_command("no server virtual $vip_name");
	$self->exit_config_mode();

	return;
}

# given a Viper::LoadBalancer:VIP object add it to the load balancer.
sub add_vip_to_load_balancer {
	my $self = shift;
	my $vip  = shift;

	if ( !$vip || !ref $vip || !$vip->isa("Viper::LoadBalancer::VIP") ) {
		confess "add_vip_to_load_balancer must be passed a Viper::LoadBalancer::VIP object";
	}

	my $vip_host = $vip->get_host_name() or confess "vip host name isn't set";
	my $port = $vip->get_port() || $self->get_config()->get_default_port();

	my $vip_name = $self->host_to_vip_name($vip_host);
	my $vip_ip   = Viper::Util::nslookup($vip_host);

	$self->enter_config_mode();
	$self->run_command(
		{
			command       => "server virtual $vip_name $vip_ip",
			success_regex => qr/\(config-vs-$vip_name\)/,
		}
	);

	$self->run_command("port default disable");

	# only enable direct server return if it is enabled for this vip in the data source
	if ( $vip->get_dsr() ) {
		$self->run_command("port $port dsr fast-delete");
	}

	$self->run_command("port $port");

	$self->exit_config_mode();

	#XXX loop through all the members and add them

	return;
}

sub get_real_servers {
	my $self = shift;

	my $config = $self->get_current_config();
	return keys %{ $config->{real_servers} };
}

sub get_real_server {
	my $self      = shift;
	my $real_name = shift;

	my $config = $self->get_current_config();
	if ( !exists $config->{real_servers}->{$real_name} ) {
		LOGDIE "real server $real_name does not exist on load balancer " . $self->get_host_name();
	}

	return $config->{real_servers}->{$real_name};
}

# iterate through all the real servers on the load balancer
# delete any of them that do not belong to a vip
sub delete_real_servers_not_in_a_vip {
	my $self = shift;

	# get a list of all vip member host names in all vips
	my @vip_members;
	my $config = $self->get_current_config();
	foreach my $vip ( keys %{ $config->{vips} } ) {
		foreach my $member ( @{ $config->{vips}->{$vip}->get_members() } ) {
			push @vip_members, $member->get_host_name();
		}
	}

	# reals and vip_members are arrays of FQDNs
	my @reals = map { $config->{real_servers}->{$_}->get_host_name() } $self->get_real_servers();
	my $lc = List::Compare->new( \@reals, \@vip_members );
	foreach my $real ( $lc->get_unique() ) {
		DEBUG "deleting real server $real from " . $self->get_host_name() . " since its not in a vip";
		$self->delete_real_server($real);
	}

	return;
}

# given the FQDN of a real server, delete it from the load balancer
sub delete_real_server {
	my $self      = shift;
	my $real_host = shift;

	my $real_name = $self->host_to_real_server_name($real_host);
	$self->no_server_real($real_name);

	return;
}

sub no_server_real {
	my $self      = shift;
	my $real_name = shift;

	$self->enter_config_mode();
	$self->run_command("no server real $real_name");

	# see docs on clear server session:
	# http://www.foundrynet.com/services/documentation/siCLI/ServerIron_CLI_Privileged_EXEC.html#176090
	$self->run_command("clear server session $real_name");
	$self->exit_config_mode();

	#XXX write some code to retry 3 times if the real still shows up
	# in the 'show server real $real_name' list.  if there's no output
	# then that real server has been deleted.

	DEBUG "sleeping 5 seconds to let changes propagate";
	sleep 5;

	return;
}

#XXX maybe this code should go in a plugin somewhere?
sub host_to_vip_name {
	my $self = shift;
	my $host = shift;

	my $vip_name = substr( $host, 0, 32 );
	if ( length $vip_name > 32 ) {

		# XXX when we trunc the names like this we need to do something to ensure there
		# aren't any collisions
		# see comments below for a hint of how to do this
		DEBUG "'$host' is greater than 32 characters, had to truncate to '$vip_name'";
	}

	return $vip_name;
}

sub host_to_real_server_name {
	my $self = shift;
	my $host = shift;

	# foundry has a limit of 32 characters
	my $real_name = substr( $host, 0, 32 );
	if ( length $host > 32 ) {

		# XXX when we trunc the names like this we need to do something to ensure there
		# aren't any collisions
		# TODO check for uniqueness like this:
		#
		# my $count = sprintf("%.3d", 0);
		# while ( $count <= 100; grep { $real_name eq $_ } keys $config->{real_servers} ) {
		#    replace the last three characters of real_name with $count
		#    $count++;
		# }
		# if ( $count >= 100 ) {
		#   LOGDIE "Couldn't get a unique name for real host $host";
		# }
		DEBUG "'$host' is greater than 32 characters, had to truncate to '$real_name'";
	}

	return $real_name;
}

sub add_member_to_vip {
	my $self     = shift;
	my $vip_host = shift;
	my $member   = shift;

	if ( !$member || !ref $member || !$member->isa("Viper::LoadBalancer::VIP::Member") ) {
		confess "add_member_to_vip must be passed a Viper::LoadBalancer::VIP::Member object";
	}

	my $member_host = $member->get_host_name();

	# first make sure the vip has been created
	my $vip_name = $self->host_to_vip_name($vip_host);
	my $config   = $self->get_current_config();
	if ( !exists $config->{vips}->{$vip_name} ) {
		LOGDIE "vip $vip_host doesn't exist in load balancer " . $self->get_host_name();
	}

	# see if this member is alread in the vip
	my @vip_member_hosts = map { $_->get_host_name() } @{ $config->{vips}->{$vip_name}->get_members() };

	if ( grep { $_ eq $member_host } @vip_member_hosts ) {
		LOGDIE "$member_host is already a member of vip $vip_host on load balancer " . $self->get_host_name();
	}

	# do a little clean up so we can avoid adding a real server twice
	$self->delete_real_servers_not_in_a_vip();

	DEBUG "Adding $member_host to $vip_host";
	my $port 
	  = $member->get_port()
	  || $self->get_config()->get_default_port()
	  || LOGDIE "No default port configured while adding member " . $member_host;
	my $health_check = $member->get_health_check();
	my $real_name = $self->add_real_server( $member->get_host_name(), $port, $health_check );

	$self->enter_config_mode();

	$self->run_command(
		{
			command       => "server virtual-name $vip_name",
			success_regex => qr/\(config-vs-$vip_name\)/,
		}
	);

	$self->run_command("bind $port $real_name $port");

	$self->exit_config_mode();

	return;

}

sub add_real_server {
	my $self         = shift;
	my $member_host  = shift or confess "missing vip member host name";
	my $port         = shift or confess "missing port";
	my $health_check = shift or confess "missing health_check";

	my $real_name      = $self->host_to_real_server_name($member_host);
	my $real_server_ip = Viper::Util::nslookup($member_host);

	$self->enter_config_mode();

	DEBUG "adding real server $real_name with ip $real_server_ip to lb " . $self->get_host_name();
	$self->run_command(
		{
			command       => "server real-name $real_name $real_server_ip",
			success_regex => qr/\(config-rs-$real_name\)/,
		}
	);

	$self->run_command("port default disable");
	$self->run_command("port $port");

	#XXX not sure about how to do this health check stuff
	$self->run_command($health_check);

	$self->exit_config_mode();

	return $real_name;
}

sub delete_member_from_vip {
	my $self        = shift;
	my $vip_host    = shift;
	my $member_host = shift;

	my $vip_name = $self->host_to_vip_name($vip_host);
	my $vip      = $self->get_vip_from_load_balancer($vip_host);
	my $vip_port = $vip->get_port() || LOGDIE "Couldn't get vip port from $vip_host";

	# find the member we're looking for so we can grab the port for it
	my $member_port;
	foreach my $member ( @{ $vip->get_members() } ) {
		if ( $member->get_host_name() eq $member_host ) {
			$member_port = $member->get_port();
			last;
		}
	}
	if ( !$member_port ) {
		LOGDIE "missing member port for host $member_host in vip $vip_host on load balancer " . $self->get_host_name();
	}

	# convert the member_host to a real name, since that's the name that was used to bind it
	my $member_name = $self->host_to_real_server_name($member_host);

	$self->enter_config_mode();

	$self->run_command("server virtual $vip_name");
	$self->run_command("no bind $vip_port $member_name $member_port");
	my @output = $self->run_command(
		{
			command       => "write memory",
			expect_output => 1
		}
	);

	DEBUG "waiting 5 seconds for the 'write memory' command to propagate";
	sleep 5;

	#XXX check that @output is
	# .Write startup-config in progress.
	# .Write startup-config done.

	$self->exit_config_mode();

	return;

}

# make sure you always leave the $exp in the state that you found it!
sub run_command {
	my $self = shift;
	my $args = shift;

	my $success_regex;
	my $command;
	my $expect_output = 0;
	if ( ref $args eq "HASH" ) {
		$command       = $args->{command};
		$success_regex = $args->{success_regex};
		$expect_output = $args->{expect_output};
	}
	else {
		if (shift) {
			confess "looks like you passed run_command several options, but not as a hash reference";
		}
		$command = $args;
	}

	# command should only be one command.  make sure they didn't stick some new
	# lines in there to try to run more than one
	if ( $command =~ /\n/) {
		LOGDIE "command '$command' isn't valid; it has new lines.  run_command only takes one command at a time";
	}

	if ( wantarray && !$expect_output ) {
		croak "run_command with command '$command' wanted an array response, but you didn't pass expect_output option";
	}

	DEBUG "running command: $command";

	my $timeout = 10;
	my $exp     = $self->get_expect();
	$exp->expect(
		$timeout,
		[
			qr/#$/ => sub {
				my $exp = shift;
				$exp->send( $command . "\r\n" );
			},
		],

		# the load balancer does this annoying thing where it asynchronously tells
		# us when a server has been deleted.  when we see this, just hit enter and get
		# a fresh prompt since there is no new line when they spit out this info
		[
			qr/Server ([^\s]*) successfully deleted\./ => sub {
				my $exp = shift;
				$exp->send("\r\n");
				exp_continue();
			},
		],
		[
			timeout => sub {
				LOGDIE "timed out while running command '$command'";
			},
		],
	);

	# this is a lame work around becase I couldn't figure out
	# how to get the output except by doing this noop
	# and then getting $exp->before
	my @output;
	$exp->expect(
		$timeout,
		[
			qr/#$/ => sub {
				my $exp = shift;
				$exp->send("\r\n");
				@output = split( "\r\n", $exp->before() );

				# remove the command from the output
				if ( $output[0] eq $command ) {
					shift @output;
				}
			},
		],
		[
			timeout => sub {
				LOGCROAK "timed out while running noop after command '$command'";
			},
		],
	);

	# if the output doesn't match the success regex die!
	my $output = join( "\n", @output );
	if ( $success_regex && $output !~ $success_regex ) {
		LOGCROAK "output for command $command doesn't match success regex.  Output was:\n $output";
	}

	# @output should only contain one line (the prompt) if they weren't expecting output
	# if there was more than one line in this case then those lines must be error messages
	if ( !$expect_output && @output > 1 ) {
		LOGCROAK "failed running command '$command' because:\n" . $output;
	}

	return @output;
}

sub get_current_config {
	my $self = shift;

	$self->enter_config_mode();

	my @output = $self->run_command(
		{
			command       => "show running-config",
			expect_output => 1,
		}
	);

	$self->exit_config_mode();

	DEBUG "looping through current config output";
	my $current_vip;
	my $config;
	my %real_host_from_name;
	foreach (@output) {

		# were looking for all the VIP definitions that are in this output.
		# we'll parse all of them.  They look something like this:
		#
		# server virtual ivip1 198.19.129.50
		#   port default disable
		#   port http
		#   bind http ixia1 http ixia2 http ixia3 http ixia4 http
		#   bind http ixia5 http ixia6 http ixia7 http ixia8 http
		# !
		#
		# this is the beginning of a VIP definition
		if (/^server virtual (\S+)\s*(\S+)/) {

			# when $current_vip is set, we're inside one of these definitions.
			$current_vip = $1;
			my $ip = $2;

			my $vip_host = eval { Viper::Util::nslookup($ip); };
			if ( !$vip_host ) {
				LOGDIE "FATAL: virtual server $current_vip with ip $ip isn't in DNS.  Delete it from the load balancer "
				  . $self->get_host_name();
			}
			else {
				$config->{vips}->{$current_vip} = Viper::LoadBalancer::VIP->new( { host_name => $vip_host } );
			}

		}

		# if we've seen the begining of a VIP definition
		if ($current_vip) {

			# all lines between the "server virtual" line and a line with an !
			# are the VIP definition so if we see an empty line, we're done
			# talking about this VIP
			if (/^!\s*$/) {
				$current_vip = undef;
				next;
			}

			#
			# get hosts from the line that looks like this:
			#   bind http ixia1 http ixia2 http ixia3 http ixia4 http
			if (/^\s*bind (.*)/) {
				my @words = split( /\s+/, $1 );

				$config->{vips}->{$current_vip}->set_port( $words[0] );

				# the odd indexes contain the host names, the even ones contain the port
				for ( my $i = 1; $words[$i]; $i += 2 ) {

					# we can't set the hostname for this member yet, because we have to
					# build a mapping between names and FQDNs.  So, we'll set the host_name
					# to the name, and then convert it after we've seen the entire config file
					$config->{vips}->{$current_vip}->add_members(
						[
							Viper::LoadBalancer::VIP::Member->new(
								{
									host_name => $words[$i],
									port      => $words[ $i + 1 ],
								}
							)
						]
					);
				}

			}
		}

		# parse out all the real servers, which look like this:
		#
		# server real ixia3 198.19.1.3
		#  port default disable
		#  port http
		#  port http url "GET /status.html HTTP/1.0"
		# !
		#
		# right now all we need to grab is the name
		#XXX include port and health check in the Viper::LoadBalancer::VIP::Member objects
		if (/^server real (\S+)\s*(\S+)/) {
			my $real_name = $1;
			my $ip        = $2;

			my $real_host = eval { Viper::Util::nslookup($ip); };
			if ( !$real_host ) {
				LOGDIE "FATAL: real server $real_name with ip $ip isn't in DNS.  Delete it from the load balancer "
				  . $self->get_host_name();
			}
			else {
				$real_host_from_name{$real_name} = $real_host;
				$config->{real_servers}->{$real_name} = Viper::LoadBalancer::VIP::Member->new( { host_name => $real_host } );
			}
		}

		# break out of this loop if we see "end" which means end of config
		if (/^end\s*$/) {
			if ( !$config ) {
				$config = {};
			}
			last;
		}
	}

	# Now that we've seen the entire config file and built a
	# real server name -> real host name mapping we can set
	# the host names of each member of each vip correctly
	foreach my $vip_name ( keys %{ $config->{vips} } ) {
		my $vip = $config->{vips}->{$vip_name};
		foreach my $member ( @{ $vip->get_members() } ) {
			my $real_name = $member->get_host_name();
			$member->set_host_name( $real_host_from_name{$real_name} );
		}
	}

	if ( !$config ) {
		LOGDIE "couldn't parse config (never saw 'end')";
	}

	return $config;
}

# return an expect object that is at the base prompt waiting for a command
# right now this all assumes that we're using line+enable authentication.
# we should support the other authen methods describe in table 6.1 here:
# http://www.foundrynet.com/services/documentation/siCLI/ServerIron_CLI_global_CONFIG.html#175745
sub get_expect {
	my $self = shift;

	if ( $self->{lb} ) {
		return $self->{lb};
	}

	my $exp = $self->connect_with_expect();

	# There are a couple of different ways the foundry load balancers handle authentication
	# One type is called password/enable.  It looks like this whenever you connect:
	#
	# User Access Verification
	#
	# Please Enter Password: *****
	#
	# User login successful.
	#
	# once you get a prompt that ends in '>' you give the 'enable' command
	# this part is handled below (so that the two password sections won't conflict)
	#
	# the other type of authentication that the foundry's do is called TACACS.  When
	# TACACS is enabled the login process looks like this:
	#
	# User Access Verification
	#
	# Please Enter Login Name: viper
	# Please Enter Password: *****
	my $spawn_ok;
	my $timeout = 3;
	$exp->expect(
		$timeout,
		[

			# we'll only get here during TACACS
			qr/Login Name:/ => sub {
				$spawn_ok = 1;
				my $fh = shift;
				$fh->send( $self->get_user_name() . "\r\n" );
				exp_continue;
			},
		],
		[
			qr/Password:/=> sub {
				$spawn_ok = 1;
				my $fh = shift;
				$fh->send( $self->get_password() . "\r\n" );
			},
		],
		[
			eof => sub {
				if ($spawn_ok) {
					LOGDIE "ERROR: premature EOF in login.\n";
				}
				else {
					LOGDIE "ERROR: could not spawn telnet.\n";
				}
			},
		],
		[
			timeout => sub {
				LOGDIE "timed out while setting up connection with load balancer " . $self->get_host_name() . "\n";
			},
		],
	);

	# now enter privileged mode (enable) and enable continuous display (skip)
	# by expecting this:
	#
	# SLB-telnet@lbf-5.pdq>enable
	# Password:*****
	#
	# SLB-telnet@lbf-5.pdq#skip
	# Disable page display mode
	# SLB-telnet@lbf-5.pdq#
	#
	# note that if we're using TACACS we won't see the > prompt and the enable
	# command isn't necessary since TACACS dumps us into an enabled console
	# (one with a # prompt).
	$exp->expect(
		$timeout,
		[

			# this is only for enable authentication (not TACACS)
			qr/Password:/=> sub {
				$spawn_ok = 1;
				my $fh = shift;
				$fh->send( $self->get_password() . "\r\n" );
				exp_continue;
			  }
		],
		[
			qr/>$/=> sub {
				my $fh = shift;
				$fh->send("enable\r\n");
				exp_continue;
			  }
		],
		[
			qr/#$/=> sub {
				my $fh = shift;
				$fh->send("skip-page-display\r\n");
			  }
		],
		[
			timeout => sub {
				LOGDIE "timed out while entering privileged mode of load balancer " . $self->get_host_name() . "\n";
			  }
		],
	);

	return $self->{lb} = $exp;
}

sub disconnect {
	my $self = shift;

	DEBUG "exiting out of the load balancer " . $self->get_host_name();

	my $timeout = 5;
	my $exp     = $self->get_expect();
	$exp->expect(
		$timeout,
		[
			qr/>$/=> sub {
				my $fh = shift;
				$fh->send("exit\r\n");
				exp_continue();
			  }
		],
		[
			qr/#$/=> sub {
				my $fh = shift;
				$fh->send("exit\r\n");
				exp_continue();
			  }
		],

		[
			eof => sub {
				DEBUG "Disconnected from load balancer " . $self->get_host_name();
			  }
		],
		[
			timeout => sub {
				LOGDIE "timed out while exiting the load balancer " . $self->get_host_name() . "\n";
			  }
		],
	);

	delete $self->{lb};

	return;

}

sub DESTROY {
	my $self = shift;

	$self->disconnect();

	return;
}

1;

__END__

=head1 NAME

Viper::LoadBalancer::Foundry

=head1 DESCRIPTION

Implementation of the Viper::LoadBalancer interface that allows you to talk to foundry equipment. 

=head1 METHODS

=over 8

=item C<< my $lb = Viper::LoadBalancer::Foundry->new( @args ) >>

See Viper::LoadBalancer documentation for description of this method.

=item C<< $lb->get_real_servers >>

Get an array of all real servers as Viper::LoadBalancer::VIP::Member objects on this load balancer.

=item C<< $lb->get_real_server( $real_name ) >>

Given the name of a real server on the load balancer, return a Viper::LoadBalancer::VIP::Member object.

=item C<< $lb->delete_real_servers_not_in_a_vip() >>

Takes no arguments.  It compares the real servers that are on the load balancer with a list of VIP members and
deletes any real servers that are not in VIPs.

=item C<< $lb->delete_real_server( $real_host_name ) >>

Given a FQDN of a real server remove it from the load balancer.  If it is in a VIP, the load balancer will automatically remove it from the VIP as well.

=item C<< my $vip_name = $lb->host_to_vip_name( $vip_host_name ) >>

Most methods take either FQDN or objects that contain FQDNs with regard to virtual and real servers.  We use this method to convert that FQDN to a unique name that meets foundry's character restrictions.

=item C<< my $real_name = $lb->host_to_real_server_name( $real_host_name) >>

Works the same as host_to_vip_name, but this is for real servers rather than virtual ones.

=item C<< $lb->add_member_to_vip( $vip_host_name, $vip_member ) >>

Given a VIP FQDN and a Viper::LoadBalancer::VIP::Member object, add the member to the VIP.

=item C<< $lb->add_real_server( $member_host, $port, $health_check ) >>

Given a real server's FQDN a port number and a health check, add this real server to the load balancer.

=item C<< $lb->delete_member_from_vip( $vip_host, $member_host ) >>

Given a VIP FQDN and member FQDN remove it from the VIP.   

=item C<< $lb->no_server_real( $real_name ) >>

Given a real server name in the load balancer, delete it

=item C<< my $config = $lb->get_current_config() >>

=item C<< my @output = $lb->run_command( $args ) >>

Run a command on the load balancer and (optionally) return the result of the command.  Valid arguments are:

    success_regex - (optional) if the output does not match this regex, die
    expect_output - (default false) if there is output, assume it is an error and die
    command - (required) a string that is the command to run

Examples:
   
    # note that the command executed and the prompt
    # are stripped from @output
    my @output = $self->run_command(
        {
            command       => "show running-config",
            expect_output => 1,
        }
    );


    # if there is output other than the prompt die
    # if the prompt does not match on '(config)' die
    $lb->run_command(
        {
            command       => "configure terminal",
            success_regex => qr/\(config\)/,
        }
    );

    # if you don't have a success_regex and you are 
    # not expected output you can just pass the command
    $lb->run_command("no server virtual foobar");

=item C<< $lb->enter_config_mode() >>

Enter into config mode to be able to make changes to the load balancers configuration

=item C<< $lb->exit_config_mode() >>

Drop out of config mode.  If you're not already in config mode, this will die

=item C<< my @vips = $lb->get_vips_from_load_balancer() >>

Return an array of Viper::LoadBalancer::VIP objects that are on this load balancer

=item C<< my $vip = $lb->get_vip_from_load_balancer( $vip_host ) >>

Given a VIP FQDN return a Viper::LoadBalancer::VIP object.  You can use the Viper::LoadBalancer::VIP->get_members object to get an array of all the Viper::LoadBalancer::VIP::Member objects that are in this VIP.

=item C<< $lb->add_vip_to_load_balancer( $vip ) >>

Given a Viper::LoadBalancer::VIP object, add it to the load balancer

=item C<< $lb->delete_vip_from_load_balancer( $vip_host ) >>

Given a VIP FQDN delete it from the load balancer

=item C<< $lb->no_server_virtual( $vip_name ) >>

Given a name in the load balancer, delete it

=item C<< my $exp = $lb->get_expect() >>

Return a Viper::Expect object that is authenticated into the load balancer.  You probably shouldn't call this directly, use run_command.

=item C<< $lb->disconnect() >>

Disconnect from the load balancer using the "exit" command

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
