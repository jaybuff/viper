package Viper::DataSource;

use strict;
use warnings;
use Carp 'croak';

sub get_load_balancers {
	croak "get_load_balancers is an abstract method, you need to extend " . __PACKAGE__ . " and implement it";
}

sub get_vips {
	croak "get_vips is an abstract method, you need to extend " . __PACKAGE__ . " and implement it";
}

sub get_vip_members {
	croak "get_vip_members is an abstract method, you need to extend " . __PACKAGE__ . " and implement it";
}

1;

__END__

=head1 NAME

Viper::DataSource - Abstract class for retrieving data for viper to use

=head1 DESCRIPTION

This is a base class for fetching data that viper will use to do it's thing.

=head1 METHODS

=over 8

=item C<< my $ds = Viper::DataSource->new() >>

=item C<< my @load_balancers = $ds->get_load_balancers() >>

Return an array of Viper::LoadBalancer objects that represent all load balancers that are under Viper control

=item C<< my @vips = $ds->get_vips( $lb_host ) >>

Given a load balancer host name, returns an array of Viper::LoadBalancer::VIP objects that represent all the VIPs on that load balancer.

=item C<< my @vip_members = $ds->get_vip_members( $vip_host, $lb_host ) >>

Given a host name for a VIP and a host name for a load balancer, return an array of Viper::LoadBalancer::VIP::Member objects that represent all the members in that VIP.

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. 
See the accompanying LICENSE file for terms.

=cut
