#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Treex::Tool::UMR::PDTV2PB::Parser;

use Scalar::Util qw{ blessed };
use Treex::Core::BundleZone;

use Test2::V0;
plan(6);

my $p = 'Treex::Tool::UMR::PDTV2PB::Parser'->new;
ok $p, 'Instantiates';
like ${ $p->dsl }, qr/ Rule \s+ ::= /x, 'Has a DSL';
ok $p->grammar, 'Has a grammar';

my $delete = $p->parse('!delete');
ok blessed($delete), 'Blessed object';
ok blessed($delete)
    && $delete->isa('Treex::Tool::UMR::PDTV2PB::Transformation::Delete'),
    'Parses delete';

my $template = $p->parse('mít-CPHR-057');
is $template->{template}, 'mít-CPHR-057', 'Parses a template';
