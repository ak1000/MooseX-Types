package DecoratorLibrary;

use MooseX::Types::Moose qw( Str ArrayRef HashRef Int );
use MooseX::Types
    -declare => [qw(
        MyArrayRefBase
        MyArrayRefInt01
        MyArrayRefInt02
        MyHashRefOfInts
        MyHashRefOfStr
        StrOrArrayRef
        AtLeastOneInt
    )];

## Some questionable messing around
    sub my_subtype {
        my ($subtype, $basetype, @rest) = @_;
        return subtype($subtype, $basetype, shift @rest, shift @rest);
    }
    
    sub my_from {
        return @_;
        
    }
    sub my_as {
        return @_;
    }
## End

subtype MyArrayRefBase,
    as ArrayRef;
    
coerce MyArrayRefBase,
    from Str,
    via {[split(',', $_)]};
    
subtype MyArrayRefInt01,
    as ArrayRef[Int];

coerce MyArrayRefInt01,
    from Str,
    via {[split('\.',$_)]},
    from HashRef,
    via {[sort values(%$_)]};
    
subtype MyArrayRefInt02,
    as MyArrayRefBase[Int];
    
subtype MyHashRefOfInts,
    as HashRef[Int];
    
subtype MyHashRefOfStr,
    as HashRef[Str];

coerce MyArrayRefInt02,
    from Str,
    via {[split(':',$_)]},
    from MyHashRefOfInts,
    via {[sort values(%$_)]},
    from MyHashRefOfStr,
    via {[ sort map { length $_ } values(%$_) ]},
    ## Can't do HashRef[ArrayRef] here since if I do HashRef get the via {}
    ## Stuff passed as args and the associated prototype messed with it.  MST
    ## seems to have a line on it but might not fix fixable.
    from (HashRef[ArrayRef]),
    via {[ sort map { @$_ } values(%$_) ]};

subtype StrOrArrayRef,
    as Str|ArrayRef;

subtype AtLeastOneInt,
    ## Same problem as MyArrayRefInt02, see above.  Another way to solve it by
    ## forcing some sort of context.  Tried to fix this with method prototypes
    ## but just couldn't make it work.
    as (ArrayRef[Int]),
    where { @$_ > 0 };

1;
