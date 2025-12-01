# sync with ../flake.nix nixConfig
{
  substituters = [
    "https://cache.nixos.org"
    "https://cache.clan.lol"
    "https://nix-community.cachix.org"
    "https://numtide.cachix.org"
    "https://cameronraysmith.cachix.org"
    "https://poetry2nix.cachix.org"
    "https://pyproject-nix.cachix.org"
    "https://om.cachix.org"
    "https://catppuccin.cachix.org"
    "https://cuda-maintainers.cachix.org"
  ];

  publicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.clan.lol-1:3KztgSAB5R1M+Dz7vzkBGzXdodizbgLXGXKXlcQLA28="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
    "poetry2nix.cachix.org-1:eXpeBJl0EQjO+vs9/1cUq19BH1LLKQT9HScbJDeeHaA="
    "pyproject-nix.cachix.org-1:UNzugsOlQIu2iOz0VyZNBQm2JSrL/kwxeCcFGw+jMe0="
    "om.cachix.org-1:ifal/RLZJKN4sbpScyPGqJ2+appCslzu7ZZF/C01f2Q="
    "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
  ];
}
