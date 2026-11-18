# The fleet's label and the private DNS domain its members and services are
# named under; `.internal` is reserved by ICANN for private use.
{ ... }:
let
  label = "vanixiets";
in
{
  flake.lib.fleet = {
    inherit label;
    domain = "${label}.internal";
  };
}
