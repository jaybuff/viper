package Viper::LoadBalancer::VIP::Member;

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

has 'health_check' => (
	is  => 'rw',
	isa => 'Str',
);

1;

__END__

=head1 NAME

Viper::LoadBalancer::VIP::Member - Object representing a member of a VIP on a load balancer

=head1 SYNOPSIS

	my $vip_member = Viper::LoadBalancer::VIP::Member->new(
		{
			host_name    => 'md1.pers.mud.yahoo.com',
			port         => 80,
			health_check => 'port http url "GET /status.html HTTP/1.0"',
		}
	);

    $vip_member->set_host_name( 'md2.pers.mud.yahoo.com' );
    $vip_member->set_port( 443 );
    $vip_member->set_health_check( 'port ssl url "GET /status.html HTTP/1.0"');

    my $host_name = $vip_member->get_host_name();
    my $port = $vip_member->get_port();
    my $health_check = $vip_member->get_health_check();

=head1 METHODS

=over 8

=item C<< my $vip_member = Viper::LoadBalancer::VIP::Member->new( $args_hashref ) >>

Create a Viper::LoadBalancer::VIP::Member object.  All values in the hash ref are optional.  

The other setters and getters should be obvious.

=item C<< $vip_member->set_host_name( $host_name ) >>
=item C<< $vip_member->set_port( $port ) >>
=item C<< $vip_member->set_health_check( $health_check ) >>
=item C<< my $host_name = $vip_member->get_host_name() >>
=item C<< my $port = $vip_member->get_port() >>
=item C<< my $health_check = $vip_member->get_health_check() >>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
