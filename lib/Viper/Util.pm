package Viper::Util;

use strict;
use warnings;

use Net::DNS::Resolver();
use IPC::Open3::Simple();
use Log::Log4perl qw(:easy);

sub nslookup {
	my $host_or_ip = shift;

	my $resolver = Net::DNS::Resolver->new();
	my $packet   = $resolver->search($host_or_ip);
	if ($packet) {
		my @answers = $packet->answer;
		foreach my $answer (@answers) {
			if ( $answer->type eq 'A' ) {
				return $answer->address;
			}
			elsif ( $answer->type eq 'PTR' ) {
				return $answer->ptrdname();
			}
		}
	}
	elsif ( $resolver->errorstring() ) {
		LOGDIE "nslookup of $host_or_ip failed because: " . $resolver->errorstring();
	}

	LOGDIE "Couldn't find DNS record for $host_or_ip";

	return;
}

# I tried Net::Netstat::Wrapper, but it caches the output of netstat on load (yuck)
sub is_port_open {
	my $port = shift;

	# output looks like this:
	# Proto Recv-Q Send-Q Local Address               Foreign Address             State
	# tcp        0      0 127.0.0.1:2300              0.0.0.0:*                   LISTEN
	#
	# we only want ports that are in listen state

    # flag to tell us if we see that the port is open in the netstat command
    my $is_port_open = 0;
	my $parse_netstat = sub {
		my @output = shift;

		foreach (@output) {
			my ( $local_address, $state ) = ( split(/\s+/) )[ 3, 5 ];
			next if ( $state !~ /^LISTEN/ );

			# the port is the last number after the last colon
			my $open_port = ( split( /:/, $local_address ) )[-1];
			next if ( $open_port !~ /^\d+$/ );
			if ( $open_port == $port ) {
                $is_port_open = 1;
                last;
			}
		}
	};

	IPC::Open3::Simple->new( out => $parse_netstat )->run('netstat -tna');

	return $is_port_open;
}


sub get_sudo_user {
    my $user = $ENV{SUDO_USER};

    if ( !$user || $user eq "root" ) {
        LOGDIE "Couldn't get the user running this command.  SUDO_USER env var is either unset or set
 to root";
    }

    return $user;
}

1;
__END__

=head1 NAME

Viper::Util - utility functions needed for the viper system

=head1 DESCRIPTION

A collection of utility functions used by viper.  Nothing is exported.

=head1 METHODS

=over 8

=item C<< my $ip = Viper::Util::nslookup( $host_name ) >>

Given a host name it looks it up in DNS and returns the IP.  Note that this can also do the reverse:

    my $host_name = Viper::Util::nslookup( $ip );

Note when used like this (passed an IP) it will always return the first A record.

=item C<< my $is_port_open = Viper::Util::is_port_open( $port ) >>

Returns true is the given tcp port on the local system is open, false otherwise.

=item C<< my $user = Viper::Util::get_sudo_user() >>

Returns SUDO_USER environment variable.  Dies if SUDO_USER is set to 'root' or undef.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
