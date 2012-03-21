#!/usr/local/bin/perl 

use Test::More 'no_plan';
use Test::Exception;
use Test::Data::Array;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../../lib";
}

use Viper::LoadBalancer::Foundry;
# for debuging
#use Log::Log4perl qw(:easy);
#Log::Log4perl->easy_init($DEBUG);

my $lb = Viper::LoadBalancer::Foundry->new( 
    {
        host_name => 'lbf-5.pdq.yahoo.com',
        jump_host => 'tftp1.pdq.corp.yahoo.com',
        user_name => 'viper',
        password  => 'viper'
    }
);

my $vip_host = 'pc.pers.vip.mud.yahoo.com';
my @vips;
lives_ok( sub { @vips = $lb->get_vips_from_load_balancer() }, "get_vips_from_load_balancer()" );


my @vip_members =  map { $_->get_host_name() } @vips;
array_once_ok( $vip_host, @vip_members, "$vip_host exists in list of vips on load balancer" );

# now delete all the vips on the host
foreach my $vip (@vips) {
	lives_ok(
		sub {
			$lb->delete_vip_from_load_balancer($vip->get_host_name()),;
		},
		"deleting vip " .  $vip->get_host_name() . " from load balancer"
	);
}

dies_ok(
	sub {
		$lb->delete_vip_from_load_balancer('foo.doesnt.exists.yahoo.com');
	},
	"deleting a vip host that doesn't exist dies"
);
