use strict;
use warnings;
package MooseX::Types::TypeDecorator;
# ABSTRACT: Wraps Moose::Meta::TypeConstraint objects with added features

our $VERSION = '0.49';

use Carp::Clan '^MooseX::Types';
use Moose::Util::TypeConstraints ();
use Moose::Meta::TypeConstraint::Union;
use Scalar::Util qw(blessed);
use namespace::autoclean 0.16;

use overload(
    '0+' => sub {
            my $self = shift @_;
            my $tc = $self->{__type_constraint};
            return 0+$tc;
     },
    # workaround for perl 5.8.5 bug
    '==' => sub { 0+$_[0] == 0+$_[1] },
    '""' => sub {
            my $self = shift @_;
            if(blessed $self) {
                return $self->__type_constraint->name;
            } else {
                return "$self";
            }
    },
    bool => sub { 1 },
    '|' => sub {

        ## It's kind of ugly that we need to know about Union Types, but this
        ## is needed for syntax compatibility.  Maybe someday we'll all just do
        ## Or[Str,Str,Int]

        my @args = @_[0,1]; ## arg 3 is special,  see the overload docs.
        my @tc = grep {blessed $_} map {
            blessed $_ ? $_ :
            Moose::Util::TypeConstraints::find_or_parse_type_constraint($_)
              || __PACKAGE__->_throw_error( "$_ is not a type constraint")
        } @args;

        ( scalar @tc == scalar @args)
            || __PACKAGE__->_throw_error(
              "one of your type constraints is bad.  Passed: ". join(', ', @args) ." Got: ". join(', ', @tc));

        ( scalar @tc >= 2 )
            || __PACKAGE__->_throw_error("You must pass in at least 2 type names to make a union");

        my $union = Moose::Meta::TypeConstraint::Union->new(type_constraints=>\@tc);
        return Moose::Util::TypeConstraints::register_type_constraint($union);
    },
    fallback => 1,
);

=head1 DESCRIPTION

This is a decorator object that contains an underlying type constraint.  We use
this to control access to the type constraint and to add some features.

=head1 METHODS

This class defines the following methods.

=head2 new

Old school instantiation

=cut

sub new {
    my $proto = shift;
    if (ref($proto)) {
        return $proto->_try_delegate('new', @_);
    }
    my $class = $proto;
    if(my $arg = shift @_) {
        if(blessed $arg && $arg->isa('Moose::Meta::TypeConstraint')) {
            return bless {'__type_constraint'=>$arg}, $class;
        } elsif(
            blessed $arg &&
            $arg->isa('MooseX::Types::UndefinedType')
          ) {
            ## stub in case we'll need to handle these types differently
            return bless {'__type_constraint'=>$arg}, $class;
        } elsif(blessed $arg) {
            __PACKAGE__->_throw_error("Argument must be ->isa('Moose::Meta::TypeConstraint') or ->isa('MooseX::Types::UndefinedType'), not ". blessed $arg);
        } else {
            __PACKAGE__->_throw_error("Argument cannot be '$arg'");
        }
    } else {
        __PACKAGE__->_throw_error("This method [new] requires a single argument.");
    }
}

=head2 __type_constraint ($type_constraint)

Set/Get the type_constraint.

=cut

sub __type_constraint {
    my $self = shift @_;
    if(blessed $self) {
        if(defined(my $tc = shift @_)) {
            $self->{__type_constraint} = $tc;
        }
        return $self->{__type_constraint};
    } else {
        __PACKAGE__->_throw_error('cannot call __type_constraint as a class method');
    }
}

=head2 C<isa>

handle C<< $self->isa >> since C<AUTOLOAD> can't - this tries both the type constraint,
and for a class type, the class.

=cut

sub isa {
  my $self = shift;
  return
    blessed $self
      ? $self->__type_constraint->isa(@_)
      || $self->_try_delegate( 'isa', @_ )
      : $self->SUPER::isa(@_);
}

=head2 can

handle $self->can since AUTOLOAD can't.

=cut

sub can {
    my $self = shift;

    return blessed $self
        ? $self->_try_delegate( 'can', @_ )
        : $self->SUPER::can(@_);
}

=head2 _throw_error

properly delegate error messages

=cut

sub _throw_error {
    shift;
    require Moose;
    unshift @_, 'Moose';
    goto &Moose::throw_error;
}

=head2 DESTROY

We might need it later

=cut

sub DESTROY {
    return;
}

=head2 AUTOLOAD

Delegate to the decorator target, unless this is a class type, in which
case it will try to delegate to the type object, then if that fails try
the class. The method 'new' is special cased to only be permitted on
the class; if there is no class, or it does not provide a new method,
an exception will be thrown.

=cut

sub AUTOLOAD {
    my ($self, @args) = @_;
    my ($method) = (our $AUTOLOAD =~ /([^:]+)$/);

    ## We delegate with this method in an attempt to support a value of
    ## __type_constraint which is also AUTOLOADing, in particular the class
    ## MooseX::Types::UndefinedType which AUTOLOADs during autovivication.

    $self->_try_delegate($method, @args);
}

sub _try_delegate {
    my ($self, $method, @args) = @_;
    my $tc = $self->__type_constraint;
    my $class;
    if ($tc->can('is_subtype_of')) { # Union can't
        my $search_tc = $tc;
        while (1) {
            if ($search_tc->isa('Moose::Meta::TypeConstraint::Class')) {
                $class = $search_tc->class;
                last;
            }
            $search_tc = $search_tc->parent;
            last unless $search_tc && $search_tc->is_subtype_of('Object');
        }
    }

    my $inv = do {
        if ($method eq 'new') {
            die "new called on type decorator for non-class-type ".$tc->name
                unless $class;
            die "new called on class type decorator ".$tc->name."\n"
                ." for class ${class}\n"
                ." which does not provide a new method - did you forget to load it?"
                unless $class->can('new');
            $class
        } elsif ($class && !$tc->can($method)) {
            $class
        } else {
            $tc
        }
    };

    $inv->$method(@args);
}

1;
