package Class::Tiny;

use strictures 1;
use Class::Tiny::_Utils;

our %MAKERS;

sub import {
  my $target = caller;
  my $class = shift;
  strictures->import;
  *{_getglob("${target}::extends")} = sub {
    *{_getglob("${target}::ISA")} = \@_;
  };
  *{_getglob("${target}::with")} = sub {
    require Role::Tiny;
    die "Only one role supported at a time by with" if @_ > 1;
    Role::Tiny->apply_role_to_package($_[0], $target);
  };
  $MAKERS{$target} = {};
  *{_getglob("${target}::has")} = sub {
    my ($name, %spec) = @_;
    ($MAKERS{$target}{accessor} ||= do {
      require Method::Generate::Accessor;
      Method::Generate::Accessor->new
    })->generate_method($target, $name, \%spec);
    $class->_constructor_maker_for($target)
          ->register_attribute_specs($name, \%spec);
  };
  foreach my $type (qw(before after around)) {
    *{_getglob "${target}::${type}"} = sub {
      _install_modifier($target, $type, @_);
    };
  }
  {
    no strict 'refs';
    @{"${target}::ISA"} = do {
      require Class::Tiny::Object; ('Class::Tiny::Object');
    } unless @{"${target}::ISA"};
  }
}

sub _constructor_maker_for {
  my ($class, $target) = @_;
  return unless $MAKERS{$target};
  $MAKERS{$target}{constructor} ||= do {
    require Method::Generate::Constructor;
    Method::Generate::Constructor
      ->new(
        package => $target,
        accessor_generator => do {
          require Method::Generate::Accessor;
          Method::Generate::Accessor->new;
        }
      )
      ->install_delayed
      ->register_attribute_specs(do {
        my @spec;
        if (my $super = do { no strict 'refs'; ${"${target}::ISA"}[0] }) {
          if (my $con = $MAKERS{$super}{constructor}) {
            @spec = %{$con->all_attribute_specs};
          }
        }
        @spec;
      });
  }
}

1;