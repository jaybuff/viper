package Viper::LoadBalancer::VIP;

use strict;
use warnings;

use Carp 'croak';
use Moose::Policy 'Moose::Policy::FollowPBP';
use Moose;

has 'host_name' => (
	is  => 'rw',
	isa => 'Str',
);

has 'port' => (
	is      => 'rw',

    # port can be something like HTTP or 80 so we'll set this of type string
	isa     => 'Str',
);

has 'dsr' => (
	isa => 'Bool',
	is  => 'rw',
);

has 'members' => (
	is  => 'rw',
	isa => 'ArrayRef[Viper::LoadBalancer::VIP::Member]',
    default => sub { [] },
);

sub add_members { 
    my $self = shift;
    my $members_ref = shift;
    
    if ( !ref $members_ref ) {
        croak "add_members takes an array reference";
    }

    $self->set_members( [ @{ $self->get_members() }, @{ $members_ref } ] );
    return;
}

1;

__END__


=head1 NAME

Viper::LoadBalancer::VIP - Object representing a VIP on a load balancer

=head1 SYNOPSIS

	# this should be an array of Viper::LoadBalancer::VIP::Member objects
	my @vip_members = ();
	my $vip         = Viper::LoadBalancer::VIP->new(
		{
			host_name => 'pc.pers.vip.mud.yahoo.com',
			port      => 80,
            dsr       => 1,
			members   => [ @vip_members ],
		}
	);


=head1 METHODS

=over 8

=item C<<my $vip = Viper::LoadBalancer::VIP->new( $args_hashref )>>
=item C<<$vip->set_host_name( $host_name )>>
=item C<<$vip->set_port( $port )>>
=item C<<$vip->set_dsr()>>
=item C<<$vip->set_members( [ @vip_members ] )>>
=item C<<$vip->add_members( [ @vip_members ] )>>
=item C<<my $host_name = $vip->get_host_name()>>
=item C<<my $port = $vip->get_port()>>
=item C<<my $dsr = $vip->get_dsr()>>
=item C<<my @vip_members = @{ $vip->get_members() } >>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
