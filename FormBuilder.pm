
# Copyright (c) 2001 Nathan Wiger <nate@wiger.org>
# Use "perldoc FormBuilder.pm" for documentation

package CGI::FormBuilder;

=head1 NAME

CGI::FormBuilder - Easily generate and process stateful forms

=head1 SYNOPSIS

    use CGI::FormBuilder;

    # Ex 1
    # Simplest version: print out a form with 3 fields
    # This is all you need for a simple form-based app!
    my $form = CGI::FormBuilder->new(fields => [qw/name job money/],
                                     title  => 'Your Occupation');
    print $form->render(header => 1);

    # Ex 1a
    # If we have default values, for example from a DBI query,
    # we can pass these in as well:
    my $dbi_results_hashref = $sth->fetchrow_hashref;
    print $form->render(values => $dbi_values_hashref);

    # Ex 1b
    # Now we're going to modify the attributes of individual
    # fields before printing them out. Normally, FormBuilder 
    # will figure this out for you automagically, but you may
    # want to customize it:

    $form->field(name  => 'job', type => 'checkbox');

    $form->field(name   => 'state', type => 'select',
                 options => \@states);
    
    print $form->render(header => 1);

    # Ex 2
    # Now we decide that we want to validate certain fields.
    # To do this we pass the 'validate' option. 

    my $valid_form = CGI::FormBuilder->new(
                        fields => [qw/name email/],
                        validate => {name  => 'WORD',
                                     email => 'EMAIL'}
                     );

    print $valid_form->render(header => 1);

    # Ex 3
    # Finally, we've decided that the builtin forms, while
    # nice, are not as pretty as we'd like them to be. So,
    # we construct a template via HTML::Template and specify
    # it as what to use during printing:

    my $nice_form = CGI::FormBuilder->new(
                        fields   => [qw/username password/],
                        template => 'userinfo.html'
                    );

    # Ex 4
    # Or, if we prefer to use the Template Toolkit (TT2),
    # we can do it like this:

    my $nice_form = CGI::FormBuilder->new(
                        fields   => [qw/username password/],
                        template => {
                              type => 'TT2',
                              template => 'userinfo.html',
                        },
                    );

    print $nice_form->render(header => 1);

    # Ex 5
    # Of course, we can even build a complete application
    # using this module, since all fields are sticky and
    # stateful across multiple submissions. And, though
    # we're using anonymous arrayrefs []'s and hashrefs {}'s
    # above there's no reason we can't use named ones:

    my $loopback_form = CGI::FormBuilder->new(
                            title    => $title,
                            fields   => \@fields,
                            values   => \%values,
                            validate => \%validate
                        );

    if ($loopback_form->submitted && $loopback_form->validate) {
        # We have a valid form that has been submitted
        # Here we would do stuff to use the different
        # values, and then finally print out a confirmation
        print $loopback_form->confirm;
    } else {
        print $loopback_form->render;
    }



=cut

use Carp;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = do { my @r=(q$Revision: 1.92 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

# use CGI for stickiness (prefer CGI::Minimal for _much_ better speed)
# we try the faster one first, since they're compatible for our needs
my $CGIMOD = 'CGI::Minimal';
eval { require CGI::Minimal };
if ($@) { require CGI; $CGIMOD = 'CGI'; }
my $CGI = '';

# For debug(), the value is set in new()
my $DEBUG;

# Catches for special validation patterns
# These are semi-Perl patterns; they must be usable by JavaScript
# as well so they do not take advantage of features JS can't use
# If the value is an arrayref, then the second arg is a tag to
# spit out at the person after the field label to help with format

my %VALID = (
    WORD  => '/^\w+$/',
    NAME  => '/^[a-zA-Z]+$/',
    NUM   => '/^-?\s*[0-9]+\.?[0-9]*$|^-?\s*\.[0-9]+$/',    # 1, 1.25, .25
    INT   => '/^-?\s*[0-9]+$/',
    FLOAT => '/^-?\s*[0-9]+\.[0-9]+$/',
    PHONE => ['/^\d{3}\-\d{3}\-\d{4}$|^\(\d{3}\)\s+\d{3}\-\d{4}$/', '123-456-7890'],
    INTPHONE => ['/^\+\d+[\s\-][\d\-\s]+$/', '+prefix local-number'],
    EMAIL => ['/^[\w\-\+\.]+\@[\w\-]+\.[\w\-\.]+$/', 'name@host.domain'],
    CARD  => '/^\d{4}[\- ]?\d{4}[\- ]?\d{4}[\- ]?\d{4}$|^\d{4}[\- ]?\d{6}[\- ]?\d{5}$/',
    MMYY  => ['/^\d{1,2}\/?\d{2}$/', 'MM/YY'],
    MMYYYY=> ['/^\d{1,2}\/?\d{4}$/', 'MM/YYYY'],
    DATE  => ['/^\d{1,2}\/\d{1,2}\/\d{4}$/', 'MM/DD/YYYY'],
    #DATE  => '/^\d{1,2}\/\d{1,2}\/\d{4}$|^\d{1,2}\/\d{4}$|^\d{1,2}\/\d{2}$/',
    ZIPCODE=> '/^\d{5}$|^\d{5}\-\d{4}$/',
    STATE => ['/^[a-zA-Z]{2}$/', 'two-letter abbr'],
    IPV4  => '/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/',  # not strictly correct (allows 555.555)
    NETMASK => '/^(\d{1,3}\.){0,3}\d{1,3}$/',
    FILE  => ['/^[\/\w\.\-]+$/', 'UNIX format'],
    WINFILE => ['/^[a-zA-Z]:\\[\\\w\s\.\-]+$/', 'Windows format'],
    MACFILE => ['/^[:\w\.\-]+$/', 'Mac format'],
    USER  => ['/^[-a-zA-Z0-9]{4,8}$/', '4-8 characters'],  # require a 4-8 char username
    HOST  => '/^[a-zA-Z0-9][-a-zA-Z0-9]*$/',
    DOMAIN=> '/^[a-zA-Z0-9][-a-zA-Z0-9\.]*\.[a-zA-Z]+$/',   # mostly correct, but allows "dom.c-o.uk"
    ETHER => '/^[\da-f]{1,2}[\.:]?[\da-f]{1,2}[\.:]?[\da-f]{1,2}[\.:]?[\da-f]{1,2}[\.:]?[\da-f]{1,2}[\.:]?[\da-f]{1,2}$/i',
    # Many thanks to Mark Belanger for these additions
    FNAME => '/^[a-zA-Z]+[- ][a-zA-Z]+$/',
    LNAME => '/^[a-zA-Z]+-?[a-zA-Z]+\s*,?(?:[a-zA-Z]+|[a-zA-Z]+\.)?$/',
    CCMM  => '/^0[1-9]|1[012]$/',
    CCYY  => '/^[1-9]{2}$/', 
);

# To clean up the HTML, instead of just allowing the HTML tags that
# we interpret are "valid", instead we yank out all the options and
# stuff that we use internally. This allows arbitrary tags to be
# specified in the generation of HTML tags. 
my @OURATTR = qw(options attr sortopts title text body validate javascript fields
                 selectnum checknum radionum table label labels comment nameopts
                 required header linebreaks sticky invalid template keepextras
                 smartness debug lalign submit reset params multiple values static
                 fieldtype fieldattr);

# trick for speedy lookup
my %OURATTR = map { $_ => 1 } @OURATTR;

sub debug { 
    return unless $DEBUG >= $_[0];  # first arg is debug level
    shift;  # using $_[0] directly above is just a little faster...
    my($func) = (caller(1))[3];
    warn "[$func] Debug: ", @_, "\n";
}

sub belch (@) {
    my($func) = (caller(1))[3];
    carp "[$func] Warning: ", @_;
}

sub puke (@) {
    my($func) = (caller(1))[3];
    croak "[$func] Fatal: ", @_;
}

sub _args (;@) {
    belch "Odd number of arguments passed into ", (caller(1))[3]
        unless (@_ % 2 == 0);
    # strip off any leading '-opt' crap
    my @args;
    while (@_) {
        (my $k = shift) =~ s/^-//;
        push @args, $k, shift;
    }
    return @args;
}

sub _data ($) {
    # auto-derefs appropriately
    my $data = shift() || return;
    if (my $ref = ref $data) {
        if ($ref eq 'ARRAY') {
            return wantarray ? @{$data} : $data;
        } elsif ($ref eq 'HASH') {
            return wantarray ? %{$data} : $data;
        } else {
            puke "Sorry, can't handle odd data ref '$ref'";
        }
    } else {
        return $data;
    }
}

sub _ismember ($@) {
    # returns 1 if is in set, undef otherwise
    # do so case-insensitively
    my $test = lc shift;
    for (@_) {
        return 1 if $test eq lc $_;
    }
    return;
}

sub _indent (;$) {
    # return proper spaces to indent x 4
    return "    " x shift();
}

sub _toname ($) {
    # creates a name from a var/file name (like file2name)
    my $name = shift || return;
    $name =~ s![^a-zA-Z0-9.-/]+! !g;
    $name =~ s!\b(\w)!\u$1!g;
    return $name;
}

sub _opt ($) {
    # This creates and returns the options needed based
    # on an $opt array/hash shifted in
    my $opt = shift;

    # "options" are the options for our select list
    my @opt = ();
    if (my $ref = ref $opt) {
        # we turn any data into ( ['key', 'val'], ['key', 'val'] )
        # have to check sub-data too, hence why this gets a little nasty
        @opt = ($ref eq 'HASH')
                  ? map { [$_, $opt->{$_}] } keys %{$opt}
                  : map { (ref $_ eq 'HASH')  ? [each %{$_}] : $_ } _data $opt;
                  #: map { (ref $_ eq 'HASH')  ? [each %{$_}] : $_
                        #: ( (ref $_ eq 'ARRAY') ? $_ : [$_, $_] ) } _data $opt;
    } else {
        # this code should not be reached, but is here for safety
        @opt = ($opt);
    }
    # iterate for debug
    #warn "[C::F] opt: $_ = @{$_}" for @opt;
 
    return @opt;
}

sub _sort (\@$) {
    # pass in the sort and ref to opts
    my @opt  = @{ shift() };
    my $sort = shift;

    if ($sort eq 'alpha') {
        @opt = sort { (_data($a))[0] cmp (_data($b))[0] } @opt;   # currently type is ignored
    } elsif ($sort eq 'numeric') {
        @opt = sort { (_data($a))[0] <=> (_data($b))[0] } @opt;
    } else {
        puke "Unsupported sort type '$sort' specified";
    }

    # return our options
    return @opt;
}

sub _initfields {

    # Resolve the fields and values, called by new() as:
    #
    #    $self->_initfields(fields => [array ref], values => {hash or obj ref});
    #
    # OR
    #
    #    $self->_initfields(fields => {hash ref of key/val pairs});
    #
    # The values are *always* taken to be the assigned values of
    # the thingy. If you need to assign other options, you need
    # to do so via the field() method.

    my $self = shift;
    my %args = _args(@_);
    my %val  = ();

    # Safety catch
    $self->{fields} ||= {};
    $self->{field_names} ||= [];

    # check to see if it be a hash or array ref
    if (ref $args{fields} eq 'HASH') {
        # with a hash ref, we setup keys/values
        $self->{field_names} = [ sort keys %{$args{fields}} ];
        while(my($k,$v) = each %{$args{fields}}) {
            $val{$k} = [_data $v]; 
            #$self->{fields}{$k}{options} = $v;
        }
        # now we lie about what $args{fields} contained so 
        # that the below data struct assembly works
        $args{fields} = $self->{field_names};
    } elsif ($args{fields}) {
        # setup our ordering
        $self->{field_names} = [ _data $args{fields} ];
    } else {
        # not resetting our fields; we're just setting up values
        $args{fields} = $self->{field_names}
            || [keys %{$args{values} || {}}];
    }

    # We currently make two passes, first getting the values
    # and then inserting them in the data struct. This could
    # probably be done in one pass, but it resulted in too many
    # lines of duplicate code. Ideas welcomed.

    if ($args{values}) {
        debug 2, "args{values} = $args{values}";
        if (UNIVERSAL::can($args{values}, 'param')) {
            # it's a blessed CGI ref or equivalent, so use its param() method
            for my $k ($args{values}->param) {
                # always assume an arrayref of values...
                my @v = $args{values}->param($k);
                $val{$k} = \@v;
            }
        } elsif (ref $args{values} eq 'HASH') {
            # must lc all the keys since we're case-insensitive
            # we turn our values hashref into an arrayref on the fly
            my @v = _data($args{values});
            while (@v) {
                my $key = lc shift @v;
                $val{$key} = [_data shift @v];
                debug 1, "walking hash: $key => @{$val{$key}}";
            }
        } else {
            puke "Unsupported operand to 'values' attribute";
        }
    }

    # Now setup our data structure. Hmm, is this the right way to
    # do this? I mean, philosophically speaking...
    for my $k (_data($args{fields})) {
        # We no longer "pre-catch" CGI. Instead, we allow stickiness
        # meaning that CGI values override our default values from above
        my @v;
        if ($CGI and @v = $CGI->param($k) and "@v") {
            debug 2, "CGI yielded $k = @v";
            $self->{fields}{$k}{value} = \@v;
            $self->{field_cgivals}{$k} = 1;
        } else {
            # we do not set the value to null if it's already
            # been manually initialized, say through a field() call
            $self->{fields}{$k}{value} = $val{$k} unless $self->{field_inited}{$k};
        }
        #debug 2, "set $k = $self->{fields}{$k}{value}";
    }

    # Finally, if the user asked for "realsmart", then we try to automatically
    # figure out some validation stuff (among other things)...
    if ($self->{opt}{smartness} && $self->{opt}{smartness} >= 2) {
        for my $field (@{$self->{field_names}}) {
            next if $self->{opt}{validate}{$field};
            if ($field =~ /email/i) {
                $self->{opt}{validate}{$field} = 'EMAIL'; 
            } elsif ($field =~ /phone/i) {
                $self->{opt}{validate}{$field} = 'PHONE';
            } elsif ($field =~ /date/i) {
                $self->{opt}{validate}{$field} = 'DATE';
            } elsif ($field =~ /credit.*card/i) {
                $self->{opt}{validate}{$field} = 'CARD';
            } elsif ($field =~ /^zipcode$/i) {
                $self->{opt}{validate}{$field} = 'ZIPCODE';
            } elsif ($field =~ /^state$/i) {
                $self->{opt}{validate}{$field} = 'STATE';
                # the options are the names of the US states
                $self->{fields}{$field}{options} =
                    [qw(AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS
                        KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC
                        ND OH OK OR PA RI SC SD TN TX UT VT WA WV WI WY)];
                debug 2, "via 'smartness' auto-determined options for '$field' field";
            } elsif ($field =~ /^file/i) {
                # guess based on the OS we're running!
                if ($^O =~ /win|dos/i) {
                    $self->{opt}{validate}{$field} = 'WINFILE';
                } elsif ($^O =~ /mac/i) {
                    $self->{opt}{validate}{$field} = 'MACFILE';
                } else {
                    $self->{opt}{validate}{$field} = 'FILE';
                }
            } elsif ($field =~ /^domain/i) {
                $self->{opt}{validate}{$field} = 'DOMAIN';
            } elsif ($field =~ /^host|host$/i) {
                $self->{opt}{validate}{$field} = 'HOST';
            } elsif ($field =~ /^user|user$/i) {
                $self->{opt}{validate}{$field} = 'USER';
            } else {
                next;   # skip below message
            }
            debug 2, "via 'smartness' set validation for '$field' field ",
                     "to '$self->{opt}{validate}{$field}'";
        }
    }

    return 1;
}

sub _escapeurl ($) {
    # minimalist, not 100% correct, URL escaping
    my $toencode = shift || return undef;
    $toencode =~ s!([^a-zA-Z0-9_,.-/])!sprintf("%%%02x",ord($1))!eg;
    return $toencode;
}

sub _escapehtml ($) {
    my $toencode = shift || return undef;
    # must do these in order or the browser won't decode right
    $toencode =~ s!&!&amp;!g;
    $toencode =~ s!<!&lt;!g;
    $toencode =~ s!>!&gt;!g;
    $toencode =~ s!"!&quot;!g;
    return $toencode;
}

sub _tag ($;@) {
    # called as _tag('tagname', %attr)
    # creates an HTML tag on the fly, quick and dirty
    my $name = shift || return;
    my @tag;
    while (@_) {
        # this cleans out all the internal junk kept in each data
        # element, returning everything else (for an html tag)
        my $key = shift;
        #if (_ismember($key, @OURATTR)) {
        if ($OURATTR{$key}) {   # faster for common case
            shift; next;
        }
        #my $val = _escapeurl shift;    # too much gets escaped
        my $val = _escapehtml shift;    # minimalist HTML escaping
        push @tag, qq($key="$val");
    }
    return '<' . join(' ', $name, sort @tag) . '>';
}

sub new {
    my $class = shift;

    # handle ->new($method) and ->new(method => $method)
    my $method = shift unless (@_ % 2 == 0);
    my %args = _args(@_);
    $args{method} ||= $method if $method;

    $DEBUG ||= delete $args{debug} || 0;   # recall that delete returns the val deleted

    # Redo our magical CGI object if specified
    # This is the *only* option that must be specified in new and not render
    if (my $r = delete $args{params}) {
        # in mod_perl, we can't do anything without a manual params => arg
        # since otherwise POST params magically disappear
        puke "Argument to 'params' option must be an object with a param() method"
            unless UNIVERSAL::can($r, 'param');
        $CGI = $r;
    } else {
        # initialize our CGI object
        #my $CGI = ($ENV{'GATEWAY_INTERFACE'} =~ /^CGI-Perl/) ? '' : $CGIMOD->new;
        $CGI = $CGIMOD->new;
    }

    # Now bless all our options into ourself
    my $self = bless {}, ref($class) || $class;
    $self->{opt} = \%args;

    # Process any fields specified, if applicable
    if (my $fields = delete $self->{opt}{fields}) {
        $self->_initfields(fields => $fields,
                           values => delete $self->{opt}{values});
    } elsif (my $values = $self->{opt}{values}) {
        $self->_initfields(values => $values);
    }

    return $self;
}

*fields = \&field;
sub field {
    my $self = shift;

    # handle either ->field($name) or ->field(name => $name)
    my $name = shift unless (@_ % 2 == 0);
    my %args = ();
    if (@_ == 2) {
        # assumed it's legacy name => value
        $args{name} = shift;
        $args{value} = shift;
    } else {
        %args = _args(@_);
        $args{name} ||= $name;
    }

    # must catch this here each time
    $self->{fields} ||= {};
    $self->{field_names} ||= [];

    debug 2, "called field(@_)";

    # no name - return ala $cgi->param
    unless ($args{name}) {
        # return an array of the names in list context, and a
        # hashref of name/value pairs in a scalar context
        if (wantarray) {
            return @{$self->{field_names}};
        } else {
            # Unfortunately, this only returns a single value
            my %ret = map { $_ => scalar $self->field($_) } @{$self->{field_names}};
            return \%ret;
        }
    }

    # push onto our order only if we don't have yet... also init
    # the field value from CGI if it exists...
    unless ($self->{fields}{"$args{name}"}) {
        #my $cgival = join $", $CGI->param($args{name});
        #$args{value} = $cgival if $cgival;
        if ($CGI && $CGI->param($args{name})) {
            #$args{value} = [ $CGI->param($args{name}) ];
            debug 1, "sticky $args{name} from CGI = " . $CGI->param($args{name});
            $self->{fields}{"$args{name}"}{value} = [ $CGI->param($args{name}) ];
            $self->{field_cgivals}{"$args{name}"} = 1;
        }
        push @{$self->{field_names}}, $args{name};
    }

    # we use this to mess around with a single field
    while(my($k,$v) = each %args) {
        next if $k eq 'name';
        # special catch for value
        debug 2, "walking field() args: $k => $v";
        if ($k eq 'value') {
            #next if $self->{field_cgivals}{"$args{name}"};  # sticky
            #debug 1, "not CGI sticky, so setting value => $v";
            debug 1, "manually forced field $args{name} value => $v";
            $self->{field_inited}{"$args{name}"} = 1;
            $v = [_data $v];
        }
        $self->{fields}{"$args{name}"}{$k} = $v;
    }

    # return the value
    my @v = _data($self->{fields}{"$args{name}"}{value});
    debug 2, "return field($args{name} => @v)";
    #return wantarray ? @v : "@v";
    return wantarray ? @v : $v[0];
}

# force return of a hash from above field function
sub values {
    puke "Sorry, CGI::FormBuilder->values is not currently supported";
    my $href = scalar shift()->field;
    # Now setup all our values
    my @ret;
    while(my($k,$v) = each %{$href}) {
       push @ret, $k, join $", @{$v->{value} || []};
    }
    return wantarray ? @ret : \@ret;
}

*output = \&render;  # unpublished, but works
sub render {
    my $self = shift;

    # lose fucking uninitialized warnings
    local $^W = 0;

    # We create our hash based on the variables set from our
    # global options, followed by those from our local sub call
    my %args = ( %{$self->{opt}}, _args(@_) );

    # We manually set these to the "defaults" because browers suck
    unless ($args{action} ||= $ENV{SCRIPT_NAME}) {
         ($args{action}) = $0 =~ m!.*/(.*)\??!;
    }
    delete $args{action} unless $args{action};
    $args{method} ||= 'GET';

    puke "You can only specify the 'params' option to ".__PACKAGE__."->new"
        if $args{params};

    # These options default to 1
    for my $def2one (qw/javascript sticky labels smartness/) {
        $args{$def2one} = 1 unless exists $args{$def2one};
    }

    # Process any fields specified, if applicable
    $self->{opt}{smartness} = $args{smartness};   # XXX kludge
    if (my $fields = delete $args{fields}) {
        $self->_initfields(fields => $fields,
                           values => delete $args{values});
    } elsif (my $values = $args{values}) {
        $self->_initfields(values => $values);
    }

    # Defaults
    unless($args{title}) {
        # here we get the name based on the executable! nifty!
        my($n) = $0 =~ m!.*/(.+)\..*!;
        $args{title} = _toname($n);
        debug 1, "auto-created the title as '$n' from script name";
    }
    $args{text}  ||= '';  # shut up "uninit in concat" in heredoc
    $args{body}  ||= { bgcolor => 'white' };

    # Thresholds for radio, checkboxes, and selects (in # of items)
    #$args{radionum}  ||= $args{checknum} || 2;
    carp "Warning: 'radionum' option is deprecated and will be ignored"
        if $args{radionum};
    $args{selectnum} ||= 5;

    my %tmplvar = %{$self->{tmplvar} || {}};  # holds stuff for HTML::Template
    my $outhtml = '';
    my $font = $args{font} ? _tag('font', face => $args{font}) : '';

    # XXX this is a major fucking hack. the only way that we
    # XXX can reliably keep state is by saving the whole
    # XXX fields part of the object and restoring it later,
    # XXX since this sub currently alters it. yeeeesh!
    # XXX yes, this has to be anonymous so it ends up a copy
    my $oldfn = [ @{$self->{field_names} ||= []} ];
    my $oldfv = { %{$self->{fields} ||= {}} };
  
    # we can also put stuff inside a table if so requested...
    my($to, $tc, $tdl, $tdo, $td2, $tdc, $tro, $trc, $co, $cc) = ('' x 9);
    unless (exists $args{table}) {
         $args{table} = 1 if @{$self->{field_names}} > 1;
    }
    if ($args{table}) { 
        # strictly speaking, these should all use _tag, but this is faster
        # currently table/tr/td attrs are not supported. should they be?
        # or should we just tell people to use a fucking template?
        $to  = '<table>';
        $tc  = '</table>';
        my $align = $args{lalign} || 'left';
        $tdl = _tag('td', align => $align) . $font;
        $tdo = "<td>$font";
        $td2 = _tag('td', colspan => 2) . $font;
        $tdc = '</td>';
        $tro = '<tr>';
        $trc = '</tr>';
        $co  = '<center>';
        $cc  = '</center>';
    }

    # Auto-sense linebreaks if not set
    $args{linebreaks} = 1 if $args{table};

    # How to handle line breaks - include <br> only if not a table
    my $br = $args{linebreaks}
                ? ($args{table} ? "\n" : "<br>\n") : '';

    # If we said that there are required fields, validate those as 'VALUE'
    if ($args{required}) {
        if ($args{required} eq 'ALL') {
            $args{validate}{$_} = 'VALUE' for @{$self->{field_names}};
        } elsif (ref $args{required} eq 'ARRAY') {
            $args{validate}{$_} = 'VALUE' for @{$args{required}};
        } else {
            belch("argument to 'required' option must be an ARRAYREF or 'ALL'");
        }
    }
        
    # For holding the JavaScript validation code
    my $jsfunc = '';
    if ($args{validate} && $args{javascript}) {
        $jsfunc .= "\n" . _tag('script', language => 'JavaScript1.2')
                 . "<!-- hide from old browsers\nfunction validate (form) {\n";
    }

    # import all our fields from our data structure and make 'em tags
    for my $field ($self->field) {

        # any attributes?
        my $attr  = $self->{fields}{$field} || {};
        debug 2, "$field:  attr = $attr / value = $attr->{value}";

        # print a label unless it's 0
        my $label = '';
        if ($args{labels} || ! exists $args{labels}) {
            $args{labels} = {} unless ref $args{labels} eq 'HASH';
            $label = $attr->{label} || $args{labels}{$field} || _toname($field);
            debug 1, "label for '$field' field set to '$label'";
        }

        # figure out how to render our little taggy-poo
        my $tag = '';

        # We setup the value separately, delete it, then reinstate later
        my $vattr = $attr->{value};
        my @value = $attr->{value} ? @{$attr->{value}} : ();
        delete $attr->{value};

        # Kill the value if we're not sticky (sticky => 0), but
        # only if we got the value from CGI (manual values aren't affected)
        @value = () if (! $args{sticky} && defined($self->{field_cgivals}{$field}));

        debug 2, "$field: retrieved value '@value' from \$attr->{value}";

        # override the type if we're printing them out statically
        $attr->{type} = 'hidden' if $args{static};

        # set default field type to fieldtype if exists
        $attr->{type} ||= $args{fieldtype} if $args{fieldtype};

        # in fact, allow a whole fieldattr thing to work globally
        if ($args{fieldattr} && ref $args{fieldattr} eq 'HASH') {
            while(my($k,$v) = each %{ $args{fieldattr} }) {
                $attr->{$k} ||= $v;
            }
        }

        # Unless the type has been set explicitly, we make a
        # guess based on how many items there are to display;
        # basically, how many options we have
        # We also catch our 'jsclick' option, which changes w/ type
        if (! $attr->{type} && ($args{smartness} || ! exists $args{smartness})) {
            if (my $ref = ref $attr->{options}) {
                debug 2, "field $field has multiple options, so setting to select|radio|checkbox";
                my $n = () = ($ref eq 'HASH') ? keys %{$attr->{options}}
                                              : @{$attr->{options}};
                $n ||= 0;
                if ($n >= $args{selectnum}) {
                    $attr->{type} = 'select';
                    $attr->{onChange} = delete $attr->{jsclick} if $attr->{jsclick};
                } else {
                    # Something is a checkbox if it is a multi-valued box.
                    # However, it is *also* a checkbox if only single-valued options,
                    # otherwise you can't unselect it.
                    if ($attr->{multiple} || @value > 1 || $n == 1) {
                        $attr->{type} = 'checkbox';
                        $attr->{onClick} = delete $attr->{jsclick} if $attr->{jsclick};
                    } else {
                        $attr->{type} = 'radio';
                        $attr->{onClick} = delete $attr->{jsclick} if $attr->{jsclick};
                    }
                }
            } elsif ($field =~ /passw[or]*d/i) {
                $attr->{type} = 'password';
                    $attr->{onChange} = delete $attr->{jsclick} if $attr->{jsclick};
            } elsif ($field =~ /(?:details?|comments?)$/i
                     || grep /\n|\r/, @value || $attr->{cols} || $attr->{rows}) {
                $attr->{type} = 'textarea';
                $attr->{onChange} = delete $attr->{jsclick} if $attr->{jsclick};
                # this is dicey, because textareas suck by default
                $attr->{cols} ||= 65;
                $attr->{rows} ||= 10;
            } else {
                $attr->{type} = 'text';
                $attr->{onChange} = delete $attr->{jsclick} if $attr->{jsclick};
            } 
            debug 2, "field $field set to type $attr->{type} automagically";
        }

        debug 1, "generating '$field' field as type '$attr->{type}' (@value)";

        # We now create the validation JavaScript, if it was requested
        # and we have a validation criterion for that specific field
        my $helptag = '';
        if ($args{validate} and my $pattern = $args{validate}{$field}) {

            # Special catch, since many would assume this would work
            if (ref $pattern eq 'Regexp') {
                puke "To use a regex in a 'validate' option you must specify ".
                     "it in single quotes, like '/^\\w+\$/' - failed on '$field' field";
            }

            # Touch a special element so that this element's label prints out bold
            # This is actually an HTML feature that must be nested here...
            $self->{fields}{$field}{required} = 1;

            if ($args{javascript}) {

                # Get the name of the field
                my $label = $self->{fields}{$field}
                            ? ($self->{fields}{$field}{label} || _toname($field))
                            : _toname($field);

                # Check our hash to see if it's a special pattern
                ($pattern, $helptag) = _data($VALID{$pattern}) if $VALID{$pattern};

                # Need some magical JavaScript crap to figure out the type of value
                # God the DOM sucks so much ass!!!! I can't believe the value element
                # changes based on the type of field!!
                my $close_brace = '';
                my $idt = 0;
                my $is_select = 0;
                my $in = _indent($idt);
                my $entry = 'did not enter a valid value';

                if ($attr->{type} eq 'select' || $attr->{type} eq 'checkbox') {

                    # get value for field from select list or checkbox
                    # always assume it is a multiple to guarantee we get all values
                    $jsfunc .= <<EOF;
$in    // select or checkbox list; always assume it's multiple to get all values
$in    var selected_$field = 0;
$in    for (var loop = 0; loop < form.$field.options.length; loop++) {
$in        if (form.$field.options[loop].selected || form.$field.options[loop].checked) {
$in            var $field = form.$field.options[loop].value;
$in            selected_$field++;
EOF
                    $close_brace = <<EOF;

$in        }
$in    } // close for loop;
$in    if (! selected_$field) {
$in        alert('You must select an option from the "$label" list');
$in        return false;
$in    }
EOF
                    $in = _indent($idt += 2);
                    $is_select++;

                } elsif ($attr->{type} eq 'radio') {

                    # get field from radio button
                    # must cycle through all again to see which is checked. yeesh.
                    $jsfunc .= <<EOF;
$in    // radio group
$in    var $field = '';
$in    for (var loop = 0; loop < form.$field.length; loop++) {
$in        if (form.$field\[loop].checked) {
$in             $field = form.$field\[loop].value;
$in        }
$in    }
EOF
                    $entry = 'must choose an option';

                } else {

                    # get value from text or other straight input
                    # at least this part makes some sense
                    $jsfunc .= <<EOF;
$in    // standard text, hidden, password, or textarea box
$in    var $field = form.$field.value;
EOF
                }

                # pre-catch: hashref is a grouping per-language
                if (ref $pattern eq 'HASH') {
                    $pattern = $pattern->{javascript} || next;
                }

                if ($pattern =~ m!^m?(.).*\1$!) {
                    # JavaScript regexp
                    $jsfunc .= qq($in    if (! $field.match($pattern)) {\n);
                } elsif (ref $pattern eq 'ARRAY') {
                    # must be w/i this set of values
                    # can you figure out how this piece of Perl works? ha ha ha ha ....
                    $jsfunc .= "$in    if ($field != '"
                             . join("' && $field != '", @{$pattern}) . "') {\n";
                } elsif ($pattern eq 'VALUE') {
                    # Not null
                    $jsfunc .= qq($in    if ((! $field && $field != 0) || $field == "") {\n);
                } else {
                    # literal string is a literal comparison, but provide
                    # a warning just in case
                    belch "Validation string '$pattern' may be a typo of a builtin pattern"
                        if ($pattern =~ /^[A-Z]+$/); 
                    $jsfunc .= qq($in    if (! ($field $pattern)) {\n);
                }

                # add on our alert message, which is unfortunately always generic
                $jsfunc .= <<EOF;
$in        alert('Error: You $entry for the "$label" field');
$in        return false;
$in    }$close_brace
EOF
            }
        }

        # Now we generate the HTML tag for each element 
        if ($attr->{type} eq 'select') {

            # "options" are the options for our select list
            my @opt = _opt($attr->{options} ||= $vattr || ['','']);
            @opt = _sort(@opt, $attr->{sortopts}) if $attr->{sortopts};

            # generate our select tag. handle multiples.
            my $mult = $attr->{multiple} || (@value > 1) ? ' multiple' : '';
            $tag = _tag("select$mult", name => $field, %{$attr});
            for my $opt (@opt) {
                # Since our data structure is a series of ['',''] things,
                # we get the name from that. If not, then it's a list
                # of regular old data that we _toname if nameopts => 1 
                my($o,$n) = (ref $opt eq 'ARRAY') ? (@{$opt}) : ($opt);
                $n ||= $attr->{nameopts} ? _toname($o) : $o;
                my $slct = _ismember($o, @value) ? ' selected' : '';
                $tag .= _tag("option$slct", value => $o) . $n . '</option>';
            }
            $tag .= '</select>';

        } elsif ($attr->{type} eq 'radio' || $attr->{type} eq 'checkbox') {
            # get our options
            my @opt = _opt($attr->{options} ||= $vattr || [1, '']);
            @opt = _sort(@opt, $attr->{sortopts}) if $attr->{sortopts};

            for my $opt (@opt) {
                # Since our data structure is a series of ['',''] things,
                # we get the name from that. If not, then it's a list
                # of regular old data that we _toname if nameopts => 1 
                my($o,$n) = (ref $opt eq 'ARRAY') ? (@{$opt}) : ($opt);
                $n ||= $attr->{nameopts} ? _toname($o) : $o;
                my $slct = _ismember($o, @value) ? ' checked' : '';
                $tag .= _tag("input$slct", name => $field, value => $o, %{$attr}) 
                      . ' ' . $n . ' ';
            }
        } elsif ($attr->{type} eq 'textarea') {
            my $text = join "\n", @value;
            $tag = _tag('textarea', name => $field, %{$attr}) . _escapehtml($text) . "</textarea>";

        } else {
            # handle default size attr
            $attr->{size} ||= $args{attr}{size} if $args{attr}{size};

            #my %value = (@value && "@value") ? (value => $value[0]) : ();
            #my $value = join $", @value;
            # we iterate over each value - this is the only reliable
            # way to handle multiple form values of the same name
            @value = (undef) unless @value; # this creates a single-element array
            for my $value (@value) {
                # setup the value
                my %value = (defined($value) && $attr->{type} ne 'password') ? (value => $value) : ();

                # special catch: we allow a type of "static" on individual fields
                # as well as the form, which will show a hidden field's value
                # XXX this doesn't work, it's more complicated than this...
                #$attr->{type} = 'hidden' if my $st = ($attr->{type} eq 'static') ? 1 : 0;

                # render the tag
                $tag .= _tag('input', name => $field, %value, %{$attr});

                # print the value out too when in a static context
                $tag .= "$value " if $attr->{type} eq 'hidden' && $args{static};
            }
        }

        # reset the value attr
        $attr->{value} = $vattr;

        # if we have a template, then we setup the tag to a tmpl_var of the
        # same name via param(). otherwise, we generate HTML rows and stuff
        my $comment = ' ' . $attr->{comment};
           if (ref $args{template} eq 'HASH' 
               && $args{template}->{type} eq 'TT2') {
                   # Template Toolkit can access complex data pretty much unaided
                   $tmplvar{field}->{$field} = {
                       %{ $self->{fields}{$field} },
                       field  => $tag . $comment,
                       values => \@value,
                       label  => $label,
                   };
           }
           elsif ($args{template}) {
            # in a template, instead of bold/red like below, we put
            # little text after the thingy
            my $req = $self->{fields}{$field}{required}
                        ? qq( <font size="-1">(required)</font>) : '';
            $req = qq(<font color="red">$req</font>) if $self->{fields}{$field}{invalid};

            # assign the template tag
            $tmplvar{"field-$field"} = $tag . $comment . $req;

            # and the value tags
            $tmplvar{"value-$field"} = $value[0];

            # create a loop for multi-values
            # we do this even for single values just so that we can
            # provide a consistent interface
            $tmplvar{"loop-$field"} = [ map { { value => $_ } } @value ];
        } 
           else {
            # bold it if so necessary
            $label = "<b>$label</b>" if $self->{fields}{$field}{required};

            # and error it too
            $label = qq(<font color="red">$label</font>) if $self->{fields}{$field}{invalid};

            # and spacing if aligned right
            $label .= '&nbsp;' if $args{lalign} eq 'right';

            # and postfix the helptag if applicable
            $helptag = '' if $args{nohelp} || $args{static};
            $helptag = qq( <font size="-1">($helptag)</font>) if $helptag;

            if ($attr->{type} eq 'hidden' && ! $args{static}) {
                # hidden fields in a non-static context get, well, hidden
                $outhtml .= $tag . $br;
            } else {
                $outhtml .= $tro . $tdl . $label . $tdc . ' ' . $tdo
                         . $tag . $comment . $helptag . $tdc . $trc . ' ' . $br;
            }
        }
    }

    # close our JavaScript if it was opened
    if ($jsfunc) {
        $jsfunc .= $args{jsfunc} if $args{jsfunc};  # extra validation stuff
        $jsfunc .= "    return true;  // all checked ok\n}\n";
        $jsfunc .= $args{jshead} if $args{jshead};  # user-defined javascript
        $jsfunc .= "//-->\n</script><noscript>"
                 . q(<font color="red"><b>Please enable JavaScript or use a newer browser</b>)
                 . q(</font></noscript>);
        # setup our form onSubmit
        # needs to be ||= so user can overrride w/ own tag
        $args{onSubmit} ||= 'return validate(this);'; 
    }

    # handle the submit/reset buttons
    # logic is a little complicated - if set but to a false value,
    # then leave off. otherwise use as the value for the tags.
    my($submit, $reset) = ('', '');
    unless ($args{static}) {
        if ($args{submit} || ! exists $args{submit}) {
            if (ref $args{submit} eq 'ARRAY') {
                # multiple buttons + JavaScript - here we go!
                for my $s (_data $args{submit}) {
                    my $js = $args{submit}
                                ? qq( onClick="this.form.submit.value = this.value;")
                                : '';
                    $submit .= _tag("input$js", name => "submit", type => 'submit',
                                value => $s);
                }
            } else {
                # show the text on the button
                $submit = _tag('input', type => 'submit', name => 'submit',
                                value => ($args{submit} || 'Submit'));
            }
        }
        if ($args{reset} || ! exists $args{reset}) {
            $reset  = _tag('input', type => 'reset', name => 'reset',
                            value => ($args{reset}  || 'Reset'));
        }
    }

    $outhtml .= $tro . $td2 . $co . $reset
              . ' '  . $submit . $cc
              . $tdc . $trc . $tc . $br;

    # closing </form> tag
    $outhtml .= "</form>";

    # and body/html
    $outhtml .= "</body></html>\n" if $args{header};

    # hidden trailer. if you perceive this as annoying, let me know and I
    # may remove it. it's supposed to help.
    #$outhtml .= "<!-- generated by CGI::FormBuilder available from cpan.org -->\n";

    # opening <form> tag: this is reversed, because our JavaScript might
    # have added an onSubmit attr. as such we have to add to the front
    # we also include a couple special state tracking tags, _submitted
    # and _sessionid.
    my $formtag = _tag('form', %args);
    my($sid, $smv) = (0, 0);
    my $smtag = '_submitted' . ($args{name} ? "_$args{name}" : '');
    if ($CGI) {
        $sid = $CGI->param('_sessionid') || '';
        $smv = ($CGI->param($smtag) || 0) + 1;
    }
    $formtag .= _tag('input', type => 'hidden', name => $smtag, value => $smv)
              . _tag('input', type => 'hidden', name => '_sessionid', value => $sid);

    # If we set keepextras, then this means that any extra fields that
    # we've set that are *not* in our fields() will be added to the form
    if ($args{keepextras} && $CGI) {
        for my $k ($CGI->param) {
            # skip leading underscore fields, previously-defined fields, and submit/reset
            next if $self->{fields}{$k} || $k =~ /^_/ || $k eq 'submit' || $k eq 'reset';
            for my $v ($CGI->param($k)) {
                $formtag .= _tag('input', type => 'hidden', name => $k, value => $v);
            }
        }
    }

    # Now assemble the top of the form
    $outhtml = $formtag . $to . $br . $outhtml;

    # FINAL STEP
    # If we're using a template, then we "simply" setup a bunch of vars
    # in %tmplvar (which is also accessible via $form->tmpl_param) and
    # then use $h->output to render the template. Otherwise, we "print"
    # the HTML we generated above verbatim by returning as a scalar.
    # 
    # NOTE: added code to handle Template Toolkit, abw November 2001
    my $header = $args{header} ? "Content-type: text/html\n\n" : '';

    if ($args{template}) {
        my (%tmplopt, $tmpltype) = ();

        if (ref $args{template} eq 'HASH') {
            %tmplopt = %{$args{template}};
            $tmpltype = $tmplopt{type} || 'HTML';
        } else {
            %tmplopt = (filename => $args{template}, die_on_bad_params => 0);
            $tmpltype = 'HTML';
        }

        if ($tmpltype eq 'HTML') {
            eval { require HTML::Template };
            puke "Can't use templates because HTML::Template is not installed!" if $@; 
            my $h = HTML::Template->new(%tmplopt);

            # a couple special fields
            $tmplvar{'form-start'}  = $formtag;
            $tmplvar{'form-submit'} = $submit;
            $tmplvar{'form-reset'}  = $reset;
            $tmplvar{'form-end'}    = '</form>';
            $tmplvar{'js-head'}     = $jsfunc;

            while(my($param, $tag) = each %tmplvar) {
                $h->param($param => $tag);
            }

            $outhtml = $header . $h->output;

        } elsif ($tmpltype eq 'TT2') {

            eval { require Template };
            puke "Can't use templates because the Template Toolkit is not installed!" if $@; 

            my ($tt2engine, $tt2template, $tt2data, $tt2var, $tt2output);
            $tt2engine = $tmplopt{engine} || { };
            $tt2engine = Template->new($tt2engine) 
                || puke $Template::ERROR unless UNIVERSAL::isa($tt2engine, 'Template');
            $tt2template = $tmplopt{template}
                || puke "tt2 template not specified";
            $tt2data = $tmplopt{data} || { };
            $tt2var = $tmplopt{variable};

            # special fields
            $tmplvar{'start'}  = $formtag;
            $tmplvar{'submit'} = $submit;
            $tmplvar{'reset'}  = $reset;
            $tmplvar{'end'}    = '</form>';
            $tmplvar{'jshead'} = $jsfunc;
            $tmplvar{'invalid'} = $self->{state}{invalid};
            $tmplvar{'fields'} = [ map $tmplvar{field}->{$_},
                   @{ $self->{field_names} } ];
            if ($tt2var) {
                $tt2data->{$tt2var} = \%tmplvar;
            } else {
                $tt2data = { %$tt2data, %tmplvar };
            }
        
            $tt2engine->process($tt2template, $tt2data, \$tt2output)
                || puke $tt2engine->error();
        
            $outhtml = $header . $tt2output;

        } else {
            puke "Invalid template type '$tmpltype' specified - can be 'HTML' or 'TT2'";
        }

    } else {

        my $body = _tag('body', %{$args{body}});

        # assemble header HTML-compliantly
        $jsfunc = "<html><head><title>$args{title}</title>$jsfunc</head>"
                . "$body$font<h3>$args{title}</h3>" if $header;

        # Insert any text we may have specified
        my $text = $args{text} || $args{text} || '';
        if (! $text) {
            if ($self->{state}{invalid}) {
                my $s = $self->{state}{invalid} == 1 ? '' : 's';
                $text = qq(Your submission had $self->{state}{invalid} error$s. Please correct )
                      . qq(the <font color="red"><b>red</b></font> fields below.\n);
            } elsif ($args{validate}) {
                $text = qq(Fields shown in <b>bold</b> are required.);
            }
        }
                    
        $outhtml = $header . $jsfunc . $text . $outhtml;
    }

    # XXX finally, reset our fields and field_names
    $self->{field_names} = $oldfn;
    $self->{fields} = $oldfv;

    return $outhtml;
}

sub confirm {

    # This is nothing more than a special wrapper around render()
    my $self = shift;
    my %args = _args(@_);
    my $date = localtime;
    $args{text} ||= qq(<b>Success!</b> Your submission has been received $date.);
    $args{static} = 1;
    return $self->render(%args);
}

sub mail {
    # This is a very generic mail handler
    my $self = shift;
    my %args = _args(@_);

    # Where does the mailer live? Must be sendmail-compatible
    my $mailer = '';
    unless ($mailer = $args{mailer}) {
        for my $sendmail (qw(/usr/lib/sendmail /usr/sbin/sendmail)) {
            if (-x $sendmail) {
                $mailer = $sendmail;
                last;
            }
        }
    }
    unless ($mailer) {
        belch "Cannot find a sendmail-compatible mailer to use";
        return;
    }

    open(MAIL, "|$mailer $args{to}") || next;
    print MAIL <<EOF;
From: $args{from}
To: $args{to}
Cc: $args{cc}
Subject: $args{subject}

$args{text}
EOF
    return close(MAIL);
}

sub mailconfirm {

    # This prints out a very generic message. This should probably
    # be much better, but I suspect very few if any people will use
    # this method. If you do, let me know and maybe I'll work on it.

    my $self = shift;
    my $to = shift unless (@_ > 1);
    my %args = _args(@_);

    # must have a "to"
    return unless $args{to} ||= $to;

    # defaults
    $args{from}    ||= 'auto-reply';
    $args{subject} ||= "$self->{opt}{title} Submission Confirmation";
    $args{text}    ||= <<EOF;
Your submission has been received and will be processed shortly. 

If you have any questions, please contact our staff by replying
to this email.
EOF
    $self->mail(%args);
}

sub mailresults {
    # This is a wrapper around mail() that sends the form results
    my $self = shift;
    my %args = _args(@_);

    # Get the field separator to use
    my $delim = $args{delimiter} || ': ';
    my $join  = $args{joiner} || $";

    # subject default
    $args{subject} ||= "$self->{opt}{title} Submission Results";

    my @form = ();
    for my $field ($self->fields) {
        my $v = join $join, $self->field($field);
        push @form, "$field$delim$v"; 
    }
    my $text = join "\n", @form;

    $self->mail(%args, text => $text);
}

sub submitted {
    # this returns the value of the submit key, if any
    my $self = shift;
    my $smtag = '_submitted' . ($self->{opt}{name} ? "_$self->{opt}{name}" : '');
    return unless $CGI;
    if ($CGI->param($smtag)) {
        # If we've been submitted, then we return the
        # value of the submit tag (which allows multiple
        # submission buttons)
        return $CGI->param('submit');
    } else {
        return;
    }
}

sub sessionid {
    # checks for the _sessoinid parameter
    return unless $CGI;
    return $CGI->param('_sessionid');
}

# This allows a crude method of delegation
sub cgi_param {
    return unless $CGI;
    shift; $CGI->param(@_);
}

# This allows us to interface with our HTML::Template
sub tmpl_param {
    my $self = shift; 
    my $key  = shift;
    @_ ? $self->{tmplvar}{$key} = shift
       : $self->{tmplvar}{$key};
}

sub validate {

    # this function does all the validation on the Perl side
    # it doesn't generate JavaScript; see render() for that...

    my $self = shift;
    my $form = $self;   # XXX alias for examples (paint-by-numbers)

    my %valid = (%{$self->{opt}{validate} || {}}, _args(@_),
                 map { $_ => 'VALUE' } @{$self->{opt}{required} || []});
    my $bad = 0;

    while(my($field, $pattern) = each %valid) {
        # fatal error if they try to validate nonexistent field
        puke "Attempt to validate non-existent field '$field'"
            unless $self->{fields}{$field};

        # loop thru, and if something isn't valid, we tag it
        #my $value = quotemeta($self->field($field) || '');
        my $oneloop = 0;
        for my $value ($self->field($field)) {
        
            # Check our hash to see if it's a special pattern
            ($pattern) = _data($VALID{$pattern}) if $VALID{$pattern};

            # pre-catch: hashref is a grouping per-language
            if (ref $pattern eq 'HASH') {
                $pattern = $pattern->{perl} || next;
            }

            if ($pattern =~ m!^m?(.).*\1$!) {
                # it be a regexp
                debug 1, "$field: does '$value' =~ $pattern?";
                unless (eval qq('$value' =~ $pattern ? 1 : 0)) {
                    $self->{fields}{$field}{invalid} = 1;
                    $bad++;
                }
            } elsif (ref $pattern eq 'ARRAY') {
                # must be w/i this set of values
                debug 1, "$field: is '$value' in (@{$pattern})?";
                unless (_ismember($value, @{$pattern})) {
                    $self->{fields}{$field}{invalid} = 1;
                    $bad++;
                }
            } elsif ($pattern eq 'VALUE') {
                # Not null
                debug 1, "$field: either '$value' || '$value' == 0?";
                unless ($value || $value == 0) {
                    $self->{fields}{$field}{invalid} = 1;
                    $bad++;
                }
            } else {
                # literal string is a literal comparison, but warn of typos...
                belch "Validation string '$pattern' may be a typo of a builtin pattern"
                    if ($pattern =~ /^[A-Z]+$/); 
                debug 1, "$field: '$value' $pattern ? 1 : 0";
                unless (eval qq('$value' $pattern ? 1 : 0)) {
                    $self->{fields}{$field}{invalid} = 1;
                    $bad++;
                }
            }
            $oneloop++;
        }
        # If not $oneloop and they asked for validation, then we
        # know that we have an error since this means no values
        unless ($oneloop) { $self->{fields}{$field}{invalid} = 1; $bad++; }
    }
    debug 2, "bad = $bad";
    $self->{state}{invalid} = $bad;
    return $bad ? 0 : 1;
}

1;

__END__

=head1 DESCRIPTION

=head2 Overview

I hate generating and processing forms. Hate it, hate it, hate it,
hate it. My forms almost always end up looking the same, and almost
always end up doing the same thing. Unfortunately, there really haven't
been any tools out there that streamline the process. Many modules
simply substitute Perl for HTML code:

    # The manual way
    print qq(<input name="email" type="text" size="20">);

    # The module way
    print input(-name => 'email', -type => 'text', -size => '20');

The problem is, that doesn't really gain you anything. You still
have just as much code. Modules like the venerable C<CGI.pm> are great
for processing parameters, but they don't save you much time when
trying to generate and process forms.

The goal of C<CGI::FormBuilder> is to provide an easy way for you
to generate and process CGI form-based applications. This module
is designed to be smart in that it figures a lot of stuff out
for you. As a result, B<FormBuilder> gives you about a B<4:1> ratio
of the code it generates versus what you have to write. 

For example, if you have multiple values for a field, it sticks them
in a radio, checkbox, or select group, depending on some factors. It
will also automatically name fields for you in human-readable labels
depending on the field names, and lay everything out in a nicely
formatted table. It will even title the form based on the name of
the script itself (C<order_form.cgi> becomes "Order Form").

Plus, B<FormBuilder> provides you full-blown validation for your
fields, including some useful builtin patterns. It will even generate
JavaScript validation routines on the fly! And, of course, it
maintains state ("stickiness") across submissions, with hooks
provided for you to plugin your own sessionid module such
as C<Apache::Session>.

And though it's smart, it allows you to customize it as well.  For
example, if you really want something to be a checkbox, you can make
it a checkbox. And, if you really want something to be output a
specific way, you can even specify the name of an C<HTML::Template> or
Template Toolkit (C<Template>) compatible template which will be
automatically filled in, statefully.

=head2 Walkthrough

Let's walk through a whole example to see how this works.
The basic usage is straightforward, and has these steps:

=over

=item 1.

Create a new C<CGI::FormBuilder> object with the proper options

=item 2.

Modify any fields that may need fiddling with

=item 3.

Validate the form, if applicable, and print it out

=back

Again, this module is designed to handle defaults intelligently
for you. In fact, a whole form-based application can be output
with nothing more than:

    use CGI::FormBuilder;

    my @fields = qw(name email password confirm_password zipcode);

    my $form = CGI::FormBuilder->new(fields => \@fields)

    print $form->render;

Not only does this generate about 4 times as much XHTML-compliant code
as the above Perl code, but it also keeps values statefully across
submissions, even when multiple values are selected. And if you
do nothing more than add the C<validate> option to C<new()>:

    my $form = CGI::FormBuilder->new(fields => \@fields, 
                                     validate => {email => 'EMAIL'});

You now get a whole set of JavaScript validation code, as well
as Perl hooks for validation. In total you get about B<6 times>
the amount of code generated versus written. Plus, statefulness
and validation are handled for you, automatically.

Let's keep building on this example. Say we decide that we really
like our form fields and their stickiness, but we need to change
a couple things. For one, we want the page to be laid out very 
precisely. No problem! We simply create an C<HTML::Template> compatible
template and tell our module to use that. The C<HTML::Template>
module uses special XHTML tags to print out variables. All you
have to do in your template is create one for each field that you're
printing, as well as one for the form header itself:

    <html>
    <head>
    <title>User Information</title>
    <tmpl_var js-head><!-- this holds the JavaScript code -->
    </head>
    <tmpl_var form-start><!-- this holds the initial form tag -->
    <h3>User Information</h3>
    Please fill out the following information:
    <!-- each of these tmpl_var's corresponds to a field -->
    <p>Your full name: <tmpl_var field-name>
    <p>Your email address: <tmpl_var field-email>
    <p>Choose a password: <tmpl_var field-password>
    <p>Please confirm it: <tmpl_var field-confirm_password>
    <p>Your home zipcode: <tmpl_var field-zipcode>
    <p>
    <tmp_var form-submit><!-- this holds the form submit button -->
    </form><!-- can also use "tmpl_var form-end", same thing -->

Then, all you need to do in your Perl is add the C<template> option:

    my $form = CGI::FormBuilder->new(fields => \@fields, 
                                     validate => {email => 'EMAIL'},
                                     template => 'userinfo.html');

And the rest of the code stays the same.

You can also do a similar thing using the Template Toolkit
(http://template-toolkit.org/) to generate the form.  This time,
specify the C<template> option as a hashref  which includes the
C<type> option set to C<TT2> and the C<template> option to denote
the name of the template you want processed.  You can also add
C<variable> as an option (among others) to denote the variable
name that you want the form data to be referenced by.

    my $form = CGI::FormBuilder->new( 
        fields => \@fields, 
        template => {
            type => 'TT2',
            template => 'userinfo.html',
            variable => 'form',
        }
    );

The template might look something like this:

    <html>
    <head>
      <title>User Information</title>
      [% form.jshead %]
    </head>
    <body>
      [% form.start %]
      <table>
        [% FOREACH field = form.fields %]
        <tr valign="top">
          <td>
            [% field.required 
                  ? "<b>$field.label</b>" 
                  : field.label 
            %]
          </td>
          <td>
            [% IF field.invalid %]
            Missing or invalid entry, please try again.
        <br/>
        [% END %]

        [% field.field %]
      </td>
    </tr>
        [% END %]
        <tr>
          <td colspan="2" align="center">
            [% form.submit %]
          </td>
        </tr>
      </table>
      [% form.end %]
    </body>
    </html>

So, as you can see, there is plugin capability for B<FormBuilder>
to basically "run" the two major templating engines, B<HTML::Template>
and B<Template Toolkit>.

Now, back to B<FormBuilder>. Let's assume that we want to validate our
form on the server side, which is common since the user may not be running
JavaScript.  All we have to add is the statement:

    $form->validate;

Which will go through the form, checking each value specified to
the validate option to see if it's ok. If there's a problem, then
that field is highlighted so that when you print it out the errors
will be apparent.

Of course, the above returns a truth value, which we should use
to see if the form was valid. That way, we can only fiddle our
database or whatever if everything looks good. We can then use
our C<confirm()> method to print out a generic results page:

    if ($form->validate) {
        # form was good, let's update database ...
        print $form->confirm;
    } else {
        print $form->render;
    }

The C<validate()> method will use whatever criteria were passed
into C<new()> via the C<validate> parameter to check the form
submission to make sure it's correct.

However, we really only want to do this after our form has been
submitted, since this could otherwise result in our form showing
errors even though the user hasn't gotten a chance to fill it
out yet. As such, we can check for whether the form has been
submitted yet by wrapping the above with:

    if ($form->submitted && $form->validate) {
        # form was good, let's update database ...
        print $form->confirm;
    } else {
        print $form->render;
    }

Of course, this module wouldn't be really smart if it didn't provide
some more stuff for you. A lot of times, we want to send a simple 
confirmation email to the user (and maybe ourselves) saying that
the form has been submitted. Just use C<mailconfirm()>:

    $form->mailconfirm(to => $email, from => $adm);

Now, any values you specify are automatically overridden by whatever 
the user enters into the form and submits. These can then be gotten
to by the C<field()> method:

    my $email = $form->field(name => 'email');

Of course, like C<CGI.pm's param()> you can just specify the name:

    my $email = $form->field('email');

B<FormBuilder> is good at giving you the data that you should
be getting. That is, let's say that you initially setup your
C<$form> object to use a hash of existing values from a database
select or something. Then, you C<render()> the form, the user
fills it out, and submits it. When you call C<field()>, you'll
get whatever the correct value is, either the default or what
the user entered across the CGI.

So, our complete code thus far looks like this:

    use CGI::FormBuilder;

    my @fields = qw(name email password confirm_password zipcode);

    my $form = CGI::FormBuilder->new(
                    fields   => \@fields, 
                    validate => {email => 'EMAIL'},
                    template => 'userinfo.html',
                    header   => 1
               );

    if ($form->submitted && $form->validate) {
        # form was good, let's update database ...

        # and send them email about their submission
        $form->mailconfirm(to => $form->field('email'), from => $adm);

        # and show a confirmation message
        print $form->confirm;
    } else {
        # print the form for them to fill out
        print $form->render;
    }

You may be surprised to learn that for many applications, the
above is probably all you'll need. Just fill in the parts that
affect what you want to do (like the database code), and you're
on your way.

=head1 REFERENCES

This really doesn't belong here, but unfortunately many people are
confused by references in Perl. Don't be - they're not that tricky.
When you take a reference, you're basically turning something into
a scalar value. Sort of. You have to do this is you want to pass
arrays intact into functions in Perl 5.

A reference is taken by preceding the variable with a backslash (\).
In our examples above, you saw something similar to this:

    my @fields = ('name', 'email');   # same as = qw(name email)

    my $form = CGI::FormBuilder->new(fields => \@fields ... );

Here, C<\@fields> is a reference. Specifically, it's an array
reference, or "arrayref" for short.

Similarly, we can do the same thing with hashes:

    my %validate = (
        name  => 'NAME';
        email => 'EMAIL',
    );

    my $form = CGI::FormBuilder->new( ... validate => \%validate);

Here, C<\%validate> is a hash reference, or "hashref".

Basically, if you don't understand references and are having trouble
wrapping your brain around them, you can try this simple rule: Any time
you're passing an array or hash into a function, you must precede it
with a backslash. Usually that's true for CPAN modules.

Finally, there are two more types of references: anonymous arrayrefs
and anonymous hashrefs. These are created with C<[]> and C<{}>,
respectively. So, for our purposes there is no real difference between
this code:

    my @fields = qw(name email);
    my %validate = (name => 'NAME', email => 'EMAIL');

    my $form = CGI::FormBuilder->new(
                    fields   => \@fields,
                    validate => \%validate
               );

And this code:

    my $form = CGI::FormBuilder->new(
                    fields   => [ qw(name email) ],
                    validate => { name => 'NAME', email => 'EMAIL' }
               );

Except that the latter doesn't require that we first create 
C<@fields> and C<%validate> variables.

Now back to our regularly-scheduled program...

=head1 FUNCTIONS

Of course, in the spirit of flexibility this module takes a bizillion
different options. None of these are mandatory - you can call the
C<new()> constructor without any fields, but your form will be really
really short. :-)

=head2 new(opt => $val, opt => $val)

This is the constructor, and must be called very first. It returns
a C<$form> object, which you can then modify and print out to create
the form. Options will be described shortly.

=head2 render(opt => $val, opt => $val)

This function renders the form into HTML, and returns a string
containing the form. The most common use is simply:

    print $form->render;

However, C<render()> accepts B<the exact same options> as C<new()>
Why? Because this allows you to set certain options at different
points in your code, which is often useful. For example, you can
change the fields depending on some conditional:

    my $form = CGI::FormBuilder->new(method => 'POST');
    if ($form->submitted) {
        # second form
        print $form->render(fields => [qw/email address/]);
    } else {
        # first form
        print $form->render(fields => [qw/name phone/]);
    }

The following are all the options accepted by both C<new()> and
C<render()>:

=over

=item action => $script

What script to point the form to. Defaults to itself, which is
the recommended setting.

=item body => \%hash

This takes a hashref of attributes that will be stuck in the
C<< <body> >> tag verbatim (for example, bgcolor, alink, etc).
If you're thinking about using this, check out the
C<template> option above (and below).

=item debug => 0 | 1 | 2

If set to 1, the module spits copious debugging info to STDERR.
If set to 2, it spits out even more gunk.  Defaults to 0.

=item fields => \@array

The C<fields> option takes an arrayref of fields to use in the form.
The fields will be printed out in the same order they are specified.
This option is needed if you expect your form to have any fields.

=item fieldtype => 'type'

This can be used to set the default type for all fields. For example,
if you're writing a survey application, you may want all of your
fields to be of type C<textarea>. Easy:

    my $form = CGI::FormBuilder->new(fields => ..., fieldtype => 'textarea');

=item fieldattr => { opt => val, opt => val }

Even more flexible than C<fieldtype>, this option allows you to 
specify I<any> type of HTML attribute and have it be the default
for all fields. For example:

    my $form = CGI::FormBuilder->new(..., fieldattr => { class => 'myClass' });

Would set the C<class> HTML attribute on all fields by default,
so that when they are printed out they will have a C<class="myClass">
part of their HTML tag.

=item font => $font

The font to use for the form. This is output as a series of
C<< <font> >> tags for best browser compatibility. If you're 
thinking about using this, check out the C<template> option
above (and below).

=item header => 1 | 0

If set to 1, a valid C<Content-type> header will be printed out.
As of version 1.69, this now defaults to 0, meaning no header
will be printed unless you specifically say C<< header => 1 >>.

=item javascript => 1 | 0

If set to 1, JavaScript is generated in addition to HTML, the
default setting.

=item jshead => JSCODE

If using JavaScript, you can also specify some JavaScript code
that will be included verbatim in the <head> section of the
document.

=item jsfunc => JSCODE

Just like C<jshead>, only this is stuff that will go into the
C<validate> JavaScript function. As such, you can use it to
add extra JavaScript validate code verbatim. Just return false
if something doesn't work. For example:

    my $jsfunc = <<EOF;
if (form.password.value == 'password') {
    alert("What are you, a moron? You used 'password' for your password?!");
    return false;
}
EOF
    ->new(... jsfunc => $jsfunc);

This is another option I don't like. Should you be using a template?

=item keepextras => 1 | 0

If set to 1, then extra parameters not set in your fields declaration
will be kept as hidden fields in the form. However, you will need
to use C<cgi_param()>, not C<field()>, to get to the values. This is
useful if you want to keep some extra parameters like referrer or
company available but not have them be valid form fields. See below
under C</"param"> for more details.

=item labels => \%hash

Like C<values>, this is a list of key/value pairs where the keys
are the names of C<fields> specified above. Normally, B<FormBuilder>
does some snazzy case and character conversion to create pretty
labels for you based on your field names. However, if you want
to explicitly name your fields, use this option.

Of course, very likely what you'll really want to do is point to
a template to use, since you probably want careful control over
your document if you're thinking about this option. See the
C<template> option above (and below).

=item lalign => 'left' | 'right' | 'center'

This is how to align the field labels in the table layout. I really
don't like this option being here, but it does turn out to be
pretty damn useful. You should probably be using a template.

=item linebreaks => 1 | 0

If set to 1, line breaks will be inserted after each input field.
By default this is figured out for you, so usually not needed.

=item method => 'POST' | 'GET'

Either C<POST> or C<GET>, the type of CGI method to use. Defaults
to C<GET> if nothing is specified.

=item name => $string

This option can B<only> be specified to C<new()> but not to C<render()>.

This names the form. It is optional, but if you specify it you must
do so in C<new()> since the name is then used to alter how variables
are created and looked up.

=item params => $object

This option can B<only> be specified to C<new()> but not to C<render()>.

This specifies an object from which the parameters should be derived.
The object must have a C<param()> method which will return values
for each parameter by name. By default a CGI object will be 
automatically created and used.

However, you will want to specify this if you're using C<mod_perl>:

    use Apache::Request;
    use CGI::FormBuilder;

    sub handler {
        my $r = Apache::Request->new(shift);
        my $form = CGI::FormBuilder->new(... params => $r);
        # ...
        print $form->render;
    }

Or, if you need to initialize a C<CGI.pm> object separately and
are using a C<POST> form method:

    use CGI;
    use CGI::FormBuilder;

    my $q = new CGI;
    my $mode = $q->param('mode');
    # do stuff based on mode ...
    my $form = CGI::FormBuilder->new(... params => $q);

The above example would allow you to access CGI parameters
directly via C<< $q->param >> (however, note that you could
get the same functionality by using C<< $form->cgi_param >>).

=item required => \@array

This is a list of those values that are required to be filled
in. These two are functionally equivalent:

    ->new(... required => [qw/name email/]);

    ->new(... validate => {name => 'VALUE', email => 'VALUE'});

So, if you just need a bunch of fields to be filled in with anything,
use this. Usually C<validate> is what you want.

=item reset => 0 | TEXT

If set to 0, then the "Reset" button is not printed. If set to 
text, then that will be printed out as the reset button. Defaults
to printing out a button that says "Reset".

=item selectnum => $threshold

These affect the "intelligence" of the module. If a given field
has any options, then it will be a radio group by default. However,
if more than C<selectnum> options are present, then it will become
a select list. The default is 5 or more options. For example:

    # This will be a radio group
    my @opt = qw(Yes No);
    $form->field(name => 'answer', options => \@opt);

    # However, this will be a select list
    my @states = qw(AK CA FL NY TX);
    $form->field(name => 'state', options => \@states);

    # This is the one special case - single items are checkboxes
    $form->field(name => 'answer', options => 'Yes');

There is no threshold for checkboxes since these are basically
a type of multiple radio select group. As such, a radio group
becomes a checkbox group if there are multiple values (not
options, but actual values) for a given field, or if you 
specify C<< multiple => 1 >> to the C<field()> method. Got it?

=item smartness => 0 | 1 | 2

By default CGI::FormBuilder tries to be pretty smart for you, like
figuring out the types of fields based on their names and number
of options. If you don't want this behavior at all, set C<smartness>
to C<0>. If you want it to be B<really> smart, like figuring
out what type of validation routines to use for you, set it to
C<2>. It defaults to C<1>.

=item static => 1 | 0

If set to 1, then the form will be output with static hidden
fields. Defaults to 0.

=item sticky => 1 | 0

Determines whether or not form values should be sticky across
submissions. Defaults to 1.

=item submit => 0 | $string | \@array

If set to 0, then the "Submit" button is not printed. It defaults
to creating a button that says "Submit" verbatim. If given an
argument, then that argument becomes the text to show. For example:

    print $form->render(submit => 'Do Lookup');

Would make it so the submit button says "Do Lookup" on it. 

If you pass an arrayref of multiple values, you get a key benefit.
This will create multiple submit buttons, each with a different value.
In addition, though, when submitted only the one that was clicked
will be sent across CGI via some JavaScript tricks. So this:

    print $form->render(submit => ['Add A Gift', 'No Thank You']);

Would create two submit buttons. Clicking on either would submit the
form, but you would be able to see which one was submitted via the
C<submitted()> function:

    my $clicked = $form->submitted;

So if the user clicked "Add A Gift" then that is what would end up
in the variable C<$clicked> above. This allows nice conditionality:

    if ($form->submitted eq 'Add A Gift') {
        # show the gift selection screen
    } elsif ($form->submitted eq 'No Thank You')
        # just process the form
    }

See the L</"EXAMPLES"> section for more details.

=item table => 1 | 0

If set to 1, the form will be neatly wrapped in a table. By default
the module decides based on how many fields there are.

=item template => $filename

This points to a filename that contains an C<HTML::Template>
compatible template to use to layout the HTML. Each of the
form fields will correspond directly to a C<< <tmpl_var> >> of
the same name prefixed with "field-" in the template. So, if
you defined a field called "email", then you would setup a
variable called C<< <tmpl_var field-email> >> in your template.

In addition, there are a couple special fields:

    <tmpl_var js-head>     -  JavaScript to stick in <head>
    <tmpl_var form-start>  -  Opening <form> tag w/ options
    <tmpl_var form-submit> -  The submit button(s)
    <tmpl_var form-reset>  -  The reset button
    <tmpl_var form-end  >  -  Closing </form> tag

However, you may want even more control. That is, maybe you want
to specify every nitty-gritty detail of your input fields, and
just want this module to take care of the statefulness of the
values. This is no problem, since this module also provides
a C<< <tmpl_var> >> with the prefix "value-" for the template.
This will I<only> contain the field's value. To clarify:

    For a field named...  The <input> tag is in  Just the value is in
    --------------------  ---------------------  --------------------
    job                   <tmpl_var field-job>   <tmpl_var value-job>
    size                  <tmpl_var field-size>  <tmpl_var value-size>
    email                 <tmpl_var field-email> <tmpl_var value-email>

Note, though, that this will only get the I<first> value in the case
of a multi-value parameter (for example, a multi-select list). To
remedy this, if there are multiple values you will also get a 
C<< <tmpl_var> >> prefixed with "loop-". So, if you had:

    myapp.cgi?color=gray&color=red&color=blue

This would give the C<color> field three values. To create a select
list, you would do this in your template:

    <select name="color" multiple>
    <tmpl_loop loop-color>
        <option value="<tmpl_var value>"><tmpl_var value></option>
    </tmpl_loop>
    </select>

In this case, each iteration the C<< <tmpl_var value> >> tag would
have one of the values of the C<color> field. The HTML would look
something like this:

    <select name="color" multiple>
        <option value="gray">gray</option>
        <option value="red">red</option>
        <option value="blue">blue</option>
    </select>

These C<< <tmpl_var> >> variables would follow the normal rules for
templates. For more details on templates, see the documentation for
C<HTML::Template>.

=item template => \%hash

You can also specify the C<template> option as a reference to a hash,
allowing you to further customise the template processing options.
In particular, this allows you to use an alternate template
processing system like the Template Toolkit.  A minimal configuration
would look like this:

    my $form = CGI::FormBuilder->new(
        fields => \@fields,
        template => {
            type => 'TT2',
            template => 'form.html',
        },
    );

The C<type> option specifies the name of the processor.  Use 
C<TT2> to invoke the Template Toolkit or C<HTML> (the default)
to invoke C<HTML::Template> as shown above.  The C<template> option
then gives the name of the template to process.

By default, the Template Toolkit makes all the form and field 
information accessible through simple variables.

    [% jshead %]  -  JavaScript to stick in <head>
    [% start  %]  -  Opening <form> tag w/ options
    [% submit %]  -  The submit button(s)
    [% reset  %]  -  The reset button
    [% end    %]  -  Closing </form> tag
    [% fields %]  -  List of fields
    [% field  %]  -  Hash of fields (for lookup by name)

You can specify the C<variable> option to have all these variables 
accessible under a certain namespace.  For example:

    my $form = CGI::FormBuilder->new(
        fields => \@fields,
        template => {
             type => 'TT2',
             template => 'form.html',
             variable => 'form'
        },
    );

With C<variable> set to C<form> the variables are accessible as:

    [% form.jshead %]
    [% form.start  %]
    etc.

You can access individual fields via the C<field> variable.

    For a field named...  The field data is in...
    --------------------  -----------------------
    job                   [% form.field.job   %]
    size                  [% form.field.size  %]
    email                 [% form.field.email %]

Each field contains various elements.  For example:

    [% myfield = form.field.email %]

    [% myfield.label    %]  # text label
    [% myfield.field    %]  # field input tag
    [% myfield.value    %]  # first value
    [% myfield.values   %]  # list of all values
    [% myfield.required %]  # required flag
    [% myfield.invalid  %]  # invalid flag

The C<fields> variable contains a list of all the fields in the form.
To iterate through all the fields in order, you could do something like
this:

    [% FOREACH field = form.fields %]
    <tr>
     <td>[% field.label %]</td> <td>[% field.field %]</td>
    </tr>
    [% END %]

If you want to customise any of the Template Toolkit options, you can
set the C<engine> option to contain a reference to an existing
C<Template> object or hash reference of options which are passed to
the C<Template> constructor.  You can also set the C<data> item to
define any additional variables you want accesible when the template
is processed.

    my $form = CGI::FormBuilder->new(
        fields => \@fields,
        template => {
             type => 'TT2',
             template => 'form.html',
             variable => 'form'
             engine   => {
                  INCLUDE_PATH => '/usr/local/tt2/templates',
             },
             data => {
                  version => 1.23,
                  author  => 'Fred Smith',
             },
        },
    );

For further details on using the Template Toolkit, see L<Template> or
http://template-toolkit.org/ .

=item text => $text

This is text that is included below the title but above the
actual form. Useful if you want to say something simple like
"Contact $adm for more help", but if you want lots of text
check out the C<template> option above.

=item title => $title

This takes a string to use as the title of the form. 

=item values => \%hash

The C<values> option takes a hashref of key/value pairs specifying
the default values for the fields. These values will be overridden
by the values entered by the user across the CGI. 

This option is useful for selecting a record from a database or
hardwiring some sensible defaults, and then including them in the
form so that the user can change them if they wish.

=item validate => \%hash

This option takes a hashref of key/value pairs, where each key
is the name of a field from the C<fields> option, and each value
is one of several things:

    - a regular expression to match the field against
    - an arrayref of values of which the field must be one
    - a string that corresponds to one of the builtin patterns
    - a string containing a literal comparison to do

And these can also be grouped together as:

    - a hashref containing pairings of comparisons to do for
      the two different languages, "javascript" and "perl"

For example, you could specify the following C<validate> params:

    my $form = CGI::FormBuilder->new(

                  fields => [qw/username password confirm_password
                                first_name last_name email/],

                  validate => { username   => [qw/nate jim bob/],
                                first_name => '/^\w+$/',    # note the 
                                last_name  => '/^\w+$/',    # single quotes!
                                email      => 'EMAIL',
                                password   => 'VALUE',
                                confirm_password => {
                                    javascript => '== form.password.value',
                                    perl       => 'eq $form->field("password")'
                                }
                              }
               );

This would create both JavaScript and Perl conditionals on the fly
that would ensure:

    - "username" was either "nate", "jim", or "bob"
    - "first_name" and "last_name" both match the regex's specified
    - "email" is a valid EMAIL format
    - "confirm_password" is equal to the "password" field

Any regular expressions you specify must be enclosed in single quotes
because they need to be used for both JavaScript and Perl code. As
such, specifying a C<qr//> will not work. Patches welcome.

Note that for both the C<javascript> and C<perl> hashref code options,
the form will be present as the variable named C<form>. For the Perl
code, you actually get a complete C<$form> object meaning that you
have full access to all its methods (although the C<field()> method
is probably the only one you'll need for validation). 

In addition to taking any regular expression you'd like, the
C<validate> option also has many builtin defaults that can
prove helpful:

    VALUE   -  is any type of non-null value
    WORD    -  is a word (\w+)
    NAME    -  matches [a-zA-Z] only
    FNAME   -  person's first name, like "Jim" or "Joe-Bob"
    LNAME   -  person's last name, like "Smith" or "King, Jr."
    NUM     -  number, decimal or integer
    INT     -  integer
    FLOAT   -  floating-point number
    PHONE   -  phone number in form "123-456-7890" or "(123) 456-7890"
    INTPHONE-  international phone number in form "+prefix local-number"
    EMAIL   -  email addr in form "name@host.domain"
    CARD    -  credit card, including Amex, with or without -'s
    DATE    -  date in format MM/DD/YYYY or DD/MM/YYYY
    MMYY    -  date in format MM/YY or MMYY
    MMYYYY  -  date in format MM/YYYY or MMYYYY
    CCMM    -  strict checking for valid credit card 2-digit month ([0-9]|1[012])
    CCYY    -  valid credit card 2-digit year
    ZIPCODE -  US postal code in format 12345 or 12345-6789
    STATE   -  valid two-letter state in all uppercase
    IPV4    -  valid IPv4 address
    NETMASK -  valid IPv4 netmask
    FILE    -  UNIX format filename (/usr/bin)
    WINFILE -  Windows format filename (C:\windows\system)
    MACFILE -  MacOS format filename (folder:subfolder:subfolder)
    HOST    -  valid hostname (some-name)
    DOMAIN  -  valid domainname (www.i-love-bacon.com)
    ETHER   -  valid ethernet address using either : or . as separators

I know the above are US-centric, but then again that's where I
live. :-) So if you need different processing just create your
own regular expression and pass it in. If there's something really
useful let me know and maybe I'll add it.

=back

Note that any other options specified are passed to the C<< <form> >>
tag verbatim. For example, you could specify C<name> and C<onSubmit>
to add the respective attributes.

=head2 field(name => $name, opt => $val, opt => $val)

This method is called on the C<$form> object you get from the C<new()>
method above, and is used to manipulate individual fields. Normally
you do not need to use this at all. However, if you want to specify
something is a certain type of input, or has a certain set of 
options, you'll need this.

For example, let's say that you create a new form:

    my $form = CGI::FormBuilder->new(fields => [qw/name state zip/]);

And that you want to make the "state" field a select list of all
the states. You would just say:

    $form->field(name => 'state', type => 'select',
                 options => \@states);

Then, when you used C<render()> to create the form output, the "state"
field would appear as a select list with the values in C<@states>
as options.

If just given the C<name> argument and no other options, then the
value of that field will be returned:

    my $email = $form->field(name => 'email');

Like C<CGI.pm's param()>, in this form the C<< name => >> is optional:

    my $email = $form->field('email');

Why is this not named C<param()>? Simple: Because it's not compatible.
Namely, while the return context behavior is the same, this function
is not responsible for retrieving all CGI parameters - only those
defined as valid form fields. This is important, as it allows your
script to accept only those field names you've defined for security.

To get the list of valid field names just call it without and args:

    my @fields = $form->field;

And to get a hashref of field/value pairs, call it as:

    my $fields = $form->field;
    my $name = $fields->{name}[0];

Note that the data structure returned will has B<all> values as
arrayrefs. As such, you must access singular elements as shown above.

The C<field()> function takes several parameters, the first of
which is mandatory. The rest are listed in alphabetical order:

=over

=item name => $name

The name of the field to manipulate. The "name =>" part is optional
if there's only one argument. For example:

    my $email = $form->field(name => 'email');
    my $email = $form->field('email');  # same thing

=item comment => $string

This prints out the given comment I<after> the field to fill
in, vebatim. For example, if you wanted a field to look like
this:

    Joke [____________] (keep it clean, please!)

You would use the following:

    $form->field(name => 'joke', comment => '(keep it clean, please!)');

The C<comment> can actually be anything you want (even another
form field). But don't tell anyone I said that.

=item jsclick => $jscode

This is a simple abstraction over directly specifying the JavaScript
action type. It is useful since if a multiple-option list changes
from C<select> to C<radio> (depending on the number of options),
then the action changes from C<onChange> to C<onClick>. Why?!?!

Example:

    $form->field(name => 'credit_card', jsclick => 'recalc_total();',
                 options => \@cards)

This would generate the following code, depending on the number
of C<@cards>:

    <select name="credit_card" onChange="recalc_total();"> ...

    <radio name="credit_card" onClick="recalc_total();"> ...

You get the idea.

=item label => $string

This will be the label printed out next to the field. By default
it will be generated automatically from the field name.

=item multiple => 1 | 0

If set to 1, then the user is allowed to choose multiple
values from the options provided. This turns radio groups
into checkboxes and selects into multi-selects. Defaults
to automatically being figured out based on number of values.

=item nameopts => 1 | 0

If set to 1, then options for select lists will be automatically
named as well. So, if you specified a list like:

    $form->field(name => 'department', 
                 options => qw[/molecular_biology philosophy psychology
                                particle_physics social_anthropology/],
                 nameopts => 1);

This would create a list like:

    <select name="department">
        <option value="molecular_biology">Molecular Biology</option>
        <option value="philosophy">Philosophy</option>
        <option value="psychology">Psychology</option>
        <option value="particle_physics">Particle Physics</option>
        <option value="social_anthropology">Social Anthropology</option>
    </select>

Basically, you get names for the options that are determined in 
the same way as the names for the fields. This is designed as
a simpler alternative to using custom C<options> data structures
if your data is regular enough to support it.

=item options => \@options | \%options

This takes an arrayref of options. It also automatically results
in the field becoming a radio (if <= 4) or select list (if > 4),
unless you explicitly set the type with the C<type> parameter.

Each item will become both the value and the text label by default.
That is, you will get something like this:

    <select name="opinion">
    <option value="yes">yes</option>
    <option value="no">no</option>
    <option value="maybe">maybe</option>
    <option value="so">so</option>
    </select>

However, if a given item is either an arrayref or hashref, then
the first element will be taken as the value and the second as the
label. So something like this:

    push @opt, ['yes', 'You betcha!'];
    push @opt, ['no', 'No way Jose'];
    push @opt, ['maybe', 'Perchance...'];
    push @opt, ['so', 'So'];
    $form->field(name => 'opinion', options => \@opt);

Would result in something like the following:

    <select name="opinion">
    <option value="yes">You betcha!</option>
    <option value="no">No way Jose</option>
    <option value="maybe">Perchance...</option>
    <option value="so">So</option>
    </select>

And this code would have the same net effect:

    push @opt, {yes => 'You betcha!'};
    push @opt, {no  => 'No way Jose'};
    push @opt, {maybe => 'Perchance...'};
    push @opt, {so  => 'So'};
    $form->field(name => 'opinion', options => \@opt);

As would, in fact, this code:

    my %opt = (
        yes => 'You betcha!',
        no  => 'No way Jose',
        maybe => 'Perchance...',
        so  => 'So'
    );
    $form->field(name => 'opinion', options => \%opt);

You get the idea. The goal is to give you as much flexibility
as possible when constructing your data structures, and this
module figures it out correctly.

For a simpler alternative, see the C<nameopts> option above

=item required => 1 | 0

If set to 1, the field must be filled in. These two are the
same:

    $form->field(name => 'email', required => 1);
    $form->field(name => 'email', validate => 'VALUE');

=item sortopts => alpha | numeric

If set, and there are options, then the options will be sorted 
in the specified order. For example:

    $form->field(name => 'category', options => \@cats,
                 sortopts => 'alpha');

Would sort the C<@cats> options in alpha order.

=item type => $type

Type of input box to make it. Default is "text", and valid values
include anything allowed by the HTML specs, including "password",
"select", "radio", "checkbox", "textarea", "hidden", and so on.

=item value => $value | \@values

The C<value> option can take either a single value or an arrayref
of multiple values. In the case of multiple values, this will
result in the field automatically becoming a multiple select list
or checkbox group, depending on the number of options specified
above.

=item validate => '/regex/'

Similar to the C<validate> option used in C<new>, this affects
the validation just of that single field. As such, rather than
a hashref, you would just specify the regex to match against.

This regex should be specified as a single-quoted string, and
NOT as a C<qr()> deal. The reason is that this needs to be
easily usable by JavaScript routines as well.

=item [htmlattr] => $value, [htmlattr] => $value

In addition to the above tags, the C<field()> function can take
any other valid HTML attribute, which will be placed in the tag
verbatim. For example, if you wanted to alter the class of the
field (if you're using stylesheets and a template, for example),
you could say:

    $form->field(name => 'email', class => 'FormField',
                 size => 80);

Then when you call C<$form->render> you would get a field something
like this:

    <input type="text" name="email" class="FormField" size="80">

(Of course, for this to really work you still have to create a class
called C<FormField> in your stylesheet.)

See also the C<fieldattr> option which can be passed to either
C<new()> or C<render()> and which provides global defaults
for all fields.

=back

=head2 cgi_param(opt => $val, opt => $val)

Wait a second, if we have C<field()> from above, why the heck
would we ever need C<cgi_param()>?

Simple. The above C<field()> function does a bunch of special
stuff. For one thing, it will only return fields which you have
explicitly defined in your form. Excess parameters will be
silently ignored. Also, it will incorporate defaults you give
it, meaning you may get a value back even though the user didn't
enter one explicitly in the form (see above).

But, you may have some times when you want extra stuff so that
you can maintain state, but you don't want it to appear in your
form. B2B and branding are easy examples:

    http://hr-outsourcing.com/newuser.cgi?company=mr_propane

This could change stuff in your form so that it showed the logo
and company name for the appropriate vendor, without polluting
your form parameters.

This call simply redispatches to C<CGI::Minimal> (if installed)
or C<CGI.pm>'s C<param()> methods, so consult those docs for 
more information.

=head2 tmpl_param(name => $val)

This allows you to interface with your C<HTML::Template> template,
if you are using one. As with C<cgi_param()> above, this is only
useful if you're manually setting non-field values. B<FormBuilder>
will automatically setup your field parameters for you; see the
L</"template"> option for more details.

=head2 confirm()

The purpose of this function is to print out a static confirmation
screen showing a short message along with the values that were
submitted. This takes a single option - C<text> - which does the 
same thing listed above. 

=head2 submitted()

This returns the value of the "Submit" button if the form has been
submitted, undef otherwise. This allows you to either test it in
a boolean context:

    if ($form->submitted) { ... }

Or to retrieve the button that was actually clicked on in the
case of multiple submit buttons:

    if ($form->submitted eq 'Update') {
        ...
    } elsif ($form->submitted eq 'Delete') {
        ...
    }

It's best to call C<validate()> in conjunction with this to make
sure the form validation works. To make sure you're getting accurate
info, it's recommended that you name your forms with the C<name>
option described above.

=head2 validate(field => '/regex/', field => '/regex/')

This validates the form based on the validation criteria passed
into C<new()> via the C<validate> option. In addition, you can
specify additional criteria to check that will be valid for just
that call of C<validate()>. This is useful is you have to deal
with different geos:

    if ($location eq 'US') {
        $form->validate(state => 'STATE', zipcode => 'ZIPCODE');
    } else {
        $form->validate(state => '/^\w{2,3}$/');
    }

Note that if you pass args to your C<validate()> function like
this, you will not get JavaScript generated or required fields
placed in bold. So, this is good for conditional validation
like the above example, but for most applications you want to
pass your validation requirements in via the C<validate>
parameter to the C<new()> function.

=head2 mailconfirm(to => $email, from => $email, cc => $email,
                   subject => $string, text => $string);

This sends a confirmation email to the named addresses. The C<to>
argument is required; everything else is optional. If no C<from>
is specified then it will be set to the address C<auto-reply>
since that is a common quasi-standard in the web app world.

This does not send any of the form results. Rather, it simply
prints out a message saying the submission was received.

=head2 mailresults(to => $email, delimiter => $delim, joiner => $join,
                   subject => $string);

This emails the form results to the specified address(es). By 
default it prints out the form results separated by a colon, such as:

    name: Nathan Wiger
    email: nate@wiger.org
    colors: red green blue

And so on. You can change this by specifying the C<delimiter> and
C<joiner> options. For example this:

    $form->mailresults(to => $to, delimiter => '=', joiner => ',');

Would produce an email like this:

    name=Nathan Wiger
    email=nate@wiger.org
    colors=red,green,blue

Note that now the last field ("colors") is separated by commas since
you have multiple values and you specified a comma as your C<joiner>.

=head2 mail(opt => $val, opt => $val)

This is a more generic version of the above; it sends whatever is
given as the C<text> argument via email verbatim to the C<to> address.
In addition, if you're not running C<sendmail> you can specify the
C<mailer> parameter to give the path of your mailer. This option
is accepted by the above functions as well.

=head2 sessionid($id)

This gets and sets the sessionid, which is stored in the special
form field C<_sessionid>. By default no session ids are generated
or used. Rather, this is intended to provide a hook for you to 
easily integrate this with a session id module like C<Apache::Session>.

Since you can set the session id via the C<_sessionid> field, you
can pass it as an argument when first showing the form:

    http://mydomain.com/forms/update_info.cgi?_sessionid=0123-091231

This would set things up so that if you called:

    my $id = $form->sessionid;

This would set C<$id> to C<0123-091231> in your script.

=head1 EXAMPLES

I find this module incredibly useful, so here are even more examples,
pasted from sample code that I've written:

=head2 Ex1: order.cgi

This example provides an order form complete with validation of the
important fields. 

    #!/usr/bin/perl -w

    use strict;
    use CGI::FormBuilder;

    my @states = qw(AL AK AZ AR CA CO CT DE DC FL GA HI ID IN IA KS
                    KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY
                    NC ND OH OK OR PA RI SC SD TN TX UT VT WA WV WI WY);

    my $form = CGI::FormBuilder->new(
                    header => 1, method => 'POST', title => 'Order Info',
                    fields => [qw/first_name last_name email address
                                  state zipcode credit_card/],
                    validate => {email => 'EMAIL', zipcode => 'ZIPCODE',
                                 credit_card => 'CARD'}
               );

    $form->field(name => 'state', options => \@states, sort => 'alpha');

    # This adds on the 'details' field to our form dynamically
    $form->field(name => 'details', cols => '50', rows => '10');

    # try to validate it first
    if ($form->submitted && $form->validate) {
        # ... more code goes here to do stuff ...
        print $form->confirm;
    } else {
        print $form->render;
    }

This will create a form called "Order Info" that will provide a pulldown
menu for the "state", a textarea for the "details", and normal text
boxes for the rest. It will then validate the fields specified to the
C<validate> option appropriately.

=head2 Ex2: order_form.cgi

This is very similar to the above, only it uses the C<smartness> option
to fill in the "state" options automatically, as well as guess at the
validation types we want. I recommend you use the C<debug> option to
see what's going on until you're sure it's doing what you want.

    #!/usr/bin/perl -w

    use strict;
    use CGI::FormBuilder;

    my $form = CGI::FormBuilder->new(
                    header => 1, method => 'POST',
                    smartness => 2, debug => 2,
                    fields => [qw/first_name last_name email address
                                  state zipcode credit_card/],
               );

    # This adds on the 'details' field to our form dynamically
    $form->field(name => 'details', cols => '50', rows => '10');

    # try to validate it first
    if ($form->submitted && $form->validate) {
        # ... more code goes here to do stuff ...
        print $form->confirm;
    } else {
        print $form->render;
    }

Since we didn't specify the C<title> option, it will be automatically
determined from the name of the executable. In this case it will be
"Order Form".

=head2 Ex3: search.cgi

This is a simple search script that uses a template to layout 
the search parameters very precisely. Note that we set our
options for our different fields and types.

    #!/usr/bin/perl -w

    use strict;
    use CGI::FormBuilder;

    my $form = CGI::FormBuilder->new(
                    header => 1, template => 'search.tmpl',
                    fields => [qw/type string status category/]
               );

    # Need to setup some specific field options
    $form->field(name => 'type',
                 options => [qw/ticket requestor hostname sysadmin/]);

    $form->field(name => 'status', type => 'radio', value => 'incomplete',
                 options => [qw/incomplete recently_completed all/]);

    $form->field(name => 'category', type => 'checkbox',
                 options => [qw/server network desktop printer/]);

    # Render the form and print it out so our submit button says "Search"
    print $form->render(submit => ' Search ');

Then, in our C<search.tmpl> HTML file, we would have something like this:

    <html>
    <head>
      <title>Search Engine</title>
      <tmpl_var js-head>
    </head>
    <body bgcolor="white">
    <center>
    <p>
    Please enter a term to search the ticket database. Make sure
    to "quote phrases".
    <p>
    <tmpl_var form-start>
    Search by <tmpl_var field-type> for <tmpl_var field-string>
    <tmpl_var form-submit>
    <p>
    Status: <tmpl_var field-status>
    <p>
    Category: <tmpl_var field-category>
    <p>
    </form>
    </body>
    </html>

That's all you need for a sticky search form with the above HTML layout.
Notice that you can change the HTML layout as much as you want without
having to touch your CGI code.

=head2 Ex4: user_info.cgi

This script grabs the user's information out of a database and lets
them update it dynamically. The DBI information is provided as an
example, your mileage may vary:

    #!/usr/bin/perl -w

    use strict;
    use CGI::FormBuilder;
    use DBI;
    use DBD::Oracle

    my $dbh = DBI->connect('dbi:Oracle:db', 'user', 'pass');

    # We create a new form. Note we've specified very little,
    # since we're getting all our values from our database.
    my $form = CGI::FormBuilder->new(
                    fields => [qw/username password confirm_password
                                  first_name last_name email/]
               );

    # Now get the value of the username from our app
    my $user = $form->cgi_param('user');
    my $sth = $dbh->prepare("select * from user_info where user = '$user'");
    $sth->execute;
    my $default_hashref = $sth->fetchrow_hashref;

    # Render our form with the defaults we got in our hashref
    print $form->render(values => $default_hashref,
                        title => "User information for '$user'");

=head1 FREQUENTLY ASKED QUESTIONS

There are a couple questions and subtle traps that seem to poke people
on a regular basis. Here are some hints.

=over

=head2 I'm confused. Why doesn't field() work like CGI's param()?

If you're used to C<CGI.pm>, you have to do a little bit of a brain
shift when working with this module.

First, this module is designed to address fields as I<abstract
entities>. That is, you don't create a "checkbox" or "radio group"
per se. Instead, you create a field named for the data you want
to collect. B<FormBuilder> takes care of figuring out what the
most optimal HTML representation is for you.

So, if you want a single-option checkbox, simply say something
like this:

    $form->field(name => 'join_mailing_list', options => 'Yes');

If you want it to be checked by default, you add the C<value> arg:

    $form->field(name  => 'join_mailing_list', options => 'Yes',
                 value => 'Yes');

You see, you're creating a field that has one possible option: "Yes".
Then, you're saying its current value is, in fact, "Yes". This will
result in B<FormBuilder> creating a single-option field (which is
a checkbox by default) and selecting the requested value (meaning
that the box will be checked).

If you want multiple values, then all you have to do is specify
multiple options:

    $form->field(name  => 'join_mailing_list', options => [qw/Yes No/],
                 value => 'Yes');

Now you'll get a radio group, and "Yes" will be selected for you!
By viewing fields as data entities (instead of HTML tags) you
get much more flexibility and less code maintenance. If you want
to be able to accept multiple values, simply add the C<multiple> arg:

    $form->field(name    => 'favorite_colors', multiple => 1,
                 options => [qw/red green blue]);

Depending on the number of C<options> you have, you'll get either
a set of checkboxes or a multiple select list (unless you manually
override this with the C<type> arg). Regardless, though, to get the
data back all you have to say is:

    my @colors = $form->field('favorite_colors');

And the rest is taken care of for you.

=head2 How do I make a multi-screen/multi-mode form?

This is easily doable, but you have to remember a couple things. Most
importantly, that B<FormBuilder> only knows about those fields you've
told it about. So, let's assume that you're going to use a special
parameter called C<mode> to control the mode of your application so
that you can call it like this:

    myapp.cgi?mode=list&...
    myapp.cgi?mode=edit&...
    myapp.cgi?mode=remove&...

And so on. You need to do two things. First, you need the C<keepextras>
option:

    my $form = CGI::FormBuilder->new(..., keepextras => 1);

This will maintain the C<mode> field as a hidden field across requests
automatically. Second, you need to realize that since the C<mode> is
not a defined field, you have to get it via the C<cgi_param()> method:

    my $mode = $form->cgi_param('mode');

This will allow you to build a large multiscreen application easily,
even integrating it with modules like C<CGI::Application> or if
you want.

You can also do this by simply defining C<mode> as a field in your
C<fields> declaration. The reason this is discouraged is because
when iterating over your fields you'll get C<mode>, which you likely
don't want (since it's not "real" data).

=head2 Why won't CGI::FormBuilder work with POST requests?

It will, but chances are you're probably doing something like this:

    use CGI qw/:standard/;
    use CGI::FormBuilder;

    # Our "mode" parameter determines what we do
    my $mode = param('mode');

    # Changed our form based on our mode
    if ($mode eq 'view') {
        my $form = CGI::FormBuilder->new(...);
    } elsif ($mode eq 'edit') {
        my $form = CGI::FormBuilder->new(...);
    }

The problem is this: Once you read a C<POST> request, it's gone
forever. In the above code, what you're doing is having C<CGI.pm>
read the C<POST> request (on the first call of C<param()>).

Luckily, there is an easy solution. First, you need to modify
your code to use the OO form of C<CGI.pm>. Then, simply specify
the C<CGI> object you create to the C<params> option of B<FormBuilder>:

    use CGI;
    use CGI::FormBuilder;

    my $cgi = CGI->new;

    # Our "mode" parameter determines what we do
    my $mode = $cgi->param('mode');

    # Changed our form based on our mode
    if ($mode eq 'view') {
        my $form = CGI::FormBuilder->new(params => $cgi, ...);
    } elsif ($mode eq 'edit') {
        my $form = CGI::FormBuilder->new(params => $cgi, ...);
    }

=head2 How do I make it so that the values aren't shown in the form?

Easy.

    my $form = CGI::FormBuilder->new(sticky => 0, ...);

By turning off the C<sticky> option, you will still be able to access
the values but they won't show up in the form.

=head2 How do I override the value of a field?

Simple, just use:

    $form->field(name => 'name_of_field', value => $value);

Note that until recently, this was totally broken. So if you're having
problems make sure you're running at least version 1.86 (which you should
be if you're reading this).

=head2 How can I change option XXX based on a conditional?

Remember that C<render()> can take any option that C<new()> can. This
means that you can set some features on your form sooner and others
later:

    my $form = CGI::FormBuilder->new(method => 'POST');

    my $mode = $form->cgi_param('mode');

    if ($mode eq 'add') {
        print $form->render(fields => [qw/name email phone/],
                            title  => 'Add a new entry');
    } elsif ($mode eq 'edit') {
        # do something to select existing values
        my %values = select_values();
        print $form->render(fields => [qw/name email phone/],
                            title  => 'Edit existing entry',
                            values => \%values);
    }

In fact, since any of the options can be used in either C<new()> or 
C<render()>, you could have specified C<fields> to C<new()> above
since they are the same for both conditions.

=head2 Can FormBuilder handle file uploads?

It sure can, and it's really easy too. Just change the C<enctype>
as an option to C<new()>:

    my $form = CGI::FormBuilder->new(enctype => 'multipart/form-data',
                                     method  => 'POST', fields => [qw/file/]);

And then get your file with:

    my $file = $form->field('file');

In fact, that's a whole file upload program right there.

=back

=head1 BUGS AND FEATURES

This has been used pretty thoroughly in a production environment
for a while now, so it's definitely stable, but I would be shocked
if it's bug-free. Bug reports and B<especially patches> to fix such
bugs are welcomed.

I'm always open to entertaining "new feature" requests, but before
sending me one, first try to work within this module's interface.
You can very likely do exactly what you want by using a template.

=head1 NOTES

Parameters beginning with a leading underscore are reserved for
future use by this module. Use at your own peril.

This module does a B<lot> of guesswork for you. This means that
sometimes (although hopefully rarely), you may be scratching your
head wondering "Why did it do that?". Just use the C<field>
method to set things up the way you want and move on.

B<FormBuilder> will try to make use of C<CGI::Minimal> if it is
available, as that module is B<much> faster than C<CGI.pm>. It
is recommended you get it and install it!

=head1 ACKNOWLEDGEMENTS

This module has really taken off, thanks to very useful input and
encouraging feedback from a number of people, including:

    Andy Wardley - huge patch enabling Template Toolkit (TT2)
    Mark Belanger - lots of helpful regex additions and bugfinding
    William Large - tons of debugging help and doc suggestions
    Kevin Lubic - tons more debugging and encouragement

There have also been a bunch of people who have pointed out bugs
and to you I am appreciative as well.

=head1 SEE ALSO

L<HTML::Template>, L<Template>, L<CGI::Minimal>, L<CGI>

=head1 VERSION

$Id: FormBuilder.pm,v 1.92 2001/12/12 22:00:43 nwiger Exp $

=head1 AUTHOR

Copyright (c) 2001 Nathan Wiger <nate@wiger.org>. All Rights 
Reserved.

This module is free software; you may copy this under the terms of
the GNU General Public License, or the Artistic License, copies of
which should have accompanied your Perl kit.

=cut

