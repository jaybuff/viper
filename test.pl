#!/usr/local/bin/perl

use strict;
use warnings;

use File::Find ();
use Test::Harness;

my @test_files;
my $wanted = sub {
	return if ( $File::Find::name !~ /\.t$/ );
	push @test_files, $File::Find::name;
};

File::Find::find( $wanted, './t/' );


@test_files = sort @test_files;
runtests(@test_files);
