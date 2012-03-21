#!/usr/local/bin/perl 

use Test::More tests => 3;
use Test::Exception;

BEGIN {
	use FindBin;
	use lib "$FindBin::Bin/../../lib";
}

use Viper::LoadBalancer::Foundry;
use Viper::LoadBalancer::VIP;

my $lb = Viper::LoadBalancer::Foundry->new( 
    {
        host_name => 'lbf-5.pdq.yahoo.com',
        jump_host => 'tftp1.pdq.corp.yahoo.com',
        user_name => 'viper',
        password  => 'viper'
    }
);

my $vip = Viper::LoadBalancer::VIP->new(
	{
		host_name    => 'pc.pers.vip.mud.yahoo.com',
		port         => 80,
	}
);
lives_ok( sub { $lb->add_vip_to_load_balancer($vip) }, "add_vip_to_load_balancer" );

# if that vip is already on the lb, this should fail
dies_ok( sub { $lb->add_vip_to_load_balancer($vip) },
	"add_vip_to_load_balancer dies if vip_host already exists" );

# if the vip host isn't resolvable then this should die
$vip->set_host_name('foobar.doesnt.exist.yahoo.com');
dies_ok( sub { $lb->add_vip_to_load_balancer($vip) },
	"add_vip_to_load_balancer dies if vip_host isn't resolvable" );
