#!/usr/bin/perl

use strict;
use Test;

# use a BEGIN block so we print our plan before CGI::FormBuilder is loaded
BEGIN { plan tests => 3 }

# Need to fake a request or else we stall
$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'ticket=111&user=pete&replacement=TRUE';

use CGI::FormBuilder;

#warn "# VERSION = $CGI::FormBuilder::VERSION\n";

# Create our template and store it in a scalarref
my $template = <<EOT;
<html>
<title>User Info</title>
Please update your info and hit "Submit".
<p>
<tmpl_var form-start>
Enter your name: <tmpl_var field-name>
<select name="color" multiple>
    <tmpl_loop loop-color>
    <option value="<tmpl_var value>" <tmpl_var selected>><tmpl_var label></option>
    </tmpl_loop>
</select>
FYI, your dress size is <tmpl_var value-size><br>
<tmpl_var form-reset> <tmpl_var form-submit>
<tmpl_var form-end>
EOT

# What options we want to use, and what we expect to see
my @test = (
    {
        opt => { fields => [qw/name color/], submit => 0, reset => 'No esta una button del submito',
                 template => { scalarref => \$template, die_on_bad_params => 0 },
               },
        mod => { color => { options => [qw/red green blue/], nameopts => 1 },
                 size  => { value => 42 } },

        res => q(<html>
<title>User Info</title>
Please update your info and hit "Submit".
<p>
<form action="03template.t" method="GET"><input name="_submitted" type="hidden" value="1"><input name="_sessionid" type="hidden" value="">
Enter your name: <input name="name" type="text">
<select name="color" multiple>
    
    <option value="red" >Red</option>
    
    <option value="green" >Green</option>
    
    <option value="blue" >Blue</option>
    
</select>
FYI, your dress size is 42<br>
<input name="reset" type="reset" value="No esta una button del submito"> 
</form>
),

    },

    {
        opt => { fields => [qw/name color size/],
                 template => { scalarref => \$template, die_on_bad_params => 0 },
                 values => {color => [qw/purple/], size => 8},
                 reset => 'Start over, boob!',
               },

        mod => { color => { options => [qw/white black other/] },
                 name => { size => 80 } },

        res => q(<html>
<title>User Info</title>
Please update your info and hit "Submit".
<p>
<form action="03template.t" method="GET"><input name="_submitted" type="hidden" value="1"><input name="_sessionid" type="hidden" value="">
Enter your name: <input name="name" size="80" type="text">
<select name="color" multiple>
    
    <option value="white" >white</option>
    
    <option value="black" >black</option>
    
    <option value="other" >other</option>
    
</select>
FYI, your dress size is 8<br>
<input name="reset" type="reset" value="Start over, boob!"> <input name="submit" type="submit" value="Submit">
</form>
),
    },

    {
        opt => { fields => [qw/name color email/], submit => [qw/Update Delete/], reset => 0,
                 template => { scalarref => \$template, die_on_bad_params => 0 },
                 values => {color => [qw/yellow green orange/]},
               },

        mod => { color => {options => [qw/red green blue yellow pink purple orange chartreuse/] },
                 size  => {value => '(unknown)' } 
               },

        res => q(<html>
<title>User Info</title>
Please update your info and hit "Submit".
<p>
<form action="03template.t" method="GET"><input name="_submitted" type="hidden" value="1"><input name="_sessionid" type="hidden" value="">
Enter your name: <input name="name" type="text">
<select name="color" multiple>
    
    <option value="red" >red</option>
    
    <option value="green" selected>green</option>
    
    <option value="blue" >blue</option>
    
    <option value="yellow" selected>yellow</option>
    
    <option value="pink" >pink</option>
    
    <option value="purple" >purple</option>
    
    <option value="orange" selected>orange</option>
    
    <option value="chartreuse" >chartreuse</option>
    
</select>
FYI, your dress size is (unknown)<br>
 <input onClick="this.form.submit.value = this.value;" name="submit" type="submit" value="Update"><input onClick="this.form.submit.value = this.value;" name="submit" type="submit" value="Delete">
</form>
),
    },

);

# Cycle thru and try it out
for (@test) {
    my $form = CGI::FormBuilder->new( %{ $_->{opt} } );
    while(my($f,$o) = each %{$_->{mod} || {}}) {
        $o->{name} = $f;
        $form->field(%$o);
    }
    ok($form->render, $_->{res});
}

