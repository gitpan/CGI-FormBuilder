#!/usr/bin/perl

use strict;
use Test;

# use a BEGIN block so we print our plan before CGI::FormBuilder is loaded
BEGIN { plan tests => 10 }

# Fake a submission request
$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'user=pete&name=Pete+Peteson&email=pete%40peteson.com&extra=junk&_submitted=1';

use CGI::FormBuilder;

# Now manually try a whole bunch of things
ok(do {
    my $form = CGI::FormBuilder->new(fields => [qw/user name email/]);
    if ($form->submitted) {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    my $form = CGI::FormBuilder->new(fields   => [qw/user name email/],
                                     validate => { email => 'EMAIL' } );
    if ($form->submitted && $form->validate) {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    # this should fail since we are saying our email should be a netmask
    my $form = CGI::FormBuilder->new(fields => [qw/user name email/],
                                     validate => { email => 'NETMASK' } );
    if ($form->submitted && $form->validate) {
        1;
    } else {
        0;
    }
}, 0);

ok(do {
    # this should also fail since the submission key will be _submitted_magic,
    # and our query_string only has _submitted in it
    my $form = CGI::FormBuilder->new(fields => [qw/user name email/],
                                     name   => 'magic');
    if ($form->submitted) {
        1;
    } else {
        0;
    }
}, 0);

ok(do {
    # CGI should override default values
    my $form = CGI::FormBuilder->new(fields => [qw/user name email/],
                                     values => { user => 'jim' } );
    if ($form->submitted && $form->field('user') eq 'pete') {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    # test a similar thing, by with mixed-case values
    my $form = CGI::FormBuilder->new(fields => [qw/user name email Addr/],
                                     values => { User => 'jim', ADDR => 'Hello' } );
    if ($form->submitted && $form->field('Addr') eq 'Hello') {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    # test a similar thing, by with mixed-case values
    my $form = CGI::FormBuilder->new(fields => { User => 'jim', ADDR => 'Hello' } );
    if ($form->submitted && ! $form->field('Addr') && $form->field('ADDR') eq 'Hello') {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    my $form = CGI::FormBuilder->new;   # no fields!
    if ($form->submitted) {
        if ($form->field('name') || $form->field('extra')) {
            # if we get here, this means that the restrictive field
            # masking is not working, and all CGI params are available
            -1;
        } elsif ($form->cgi_param('name')) {
            1;
        } else {
            0;
        }
    } else {
            0;
    }
}, 1);

ok(do {
    # test a similar thing, by with mixed-case values
    my $form = CGI::FormBuilder->new(fields => { User => 'jim', ADDR => 'Hello' } );
    if ($form->submitted && ! $form->field('Addr') && $form->field('ADDR') eq 'Hello') {
        1;
    } else {
        0;
    }
}, 1);

ok(do {
    # test a similar thing, by with mixed-case values
    my $form = CGI::FormBuilder->new(fields => { User => 'jim', ADDR => 'Hello' } );
    if ($form->submitted && ! $form->field('Addr') && $form->field('ADDR') eq 'Hello') {
        1;
    } else {
        0;
    }
}, 1);

