#!/usr/local/bin/perl

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME          => 'Viper',
	AUTHOR        => 'Jay Buffington <jaybuffington@gmail.com>',
	VERSION_FROM  => 'lib/Viper.pm',
	ABSTRACT_FROM => 'lib/Viper.pm',
	PL_FILES      => {},
	PREREQ_PM     => {
		'Config::YAML'         => 0,
		'Expect'               => 0,
		'IPC::Open3::Simple'   => 0,
		'List::Compare'        => 0,
		'Log::Dispatch'        => 0,
		'Log::Log4perl'        => 0,
		'Module::Load'         => 0,
		'Moose'                => 0,
		'Moose::Policy'        => 0,
		'Pod::Coverage::Moose' => 0,
		'Net::DNS'             => 0,
		'Net::Telnet'          => 0,
		'Test::Data'           => 0,
		'Test::Exception'      => 0,
		'Test::More'           => 0,
		'Test::Pod'            => 0,
		'Test::Pod::Coverage'  => 0,
		'version'              => 0,
	},
	dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean => { FILES    => 'Viper-*' },
);
