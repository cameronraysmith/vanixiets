"""Write confinement and request policy (design D5)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import PurePosixPath
from typing import override
from urllib.parse import urlsplit

from expression import Error, Ok, Result

from realize_pin.capabilities import Http, Method
from realize_pin.model import (
    GitCommit,
    GithubRelease,
    Npm,
    Plan,
    PlanAsset,
    PlanDerived,
    PlanFetchFromGitHub,
    PlanFile,
    PlanFileValue,
    PlanPlatformBinaries,
    PlanRuntimeFetch,
    PlanUpstreamFile,
    Prefetch,
    Pin,
    Pypi,
    Source,
    VendorJson,
    VendorText,
)

FORGE_API_HOSTS = frozenset({"api.github.com"})


def pin_path(package: str) -> str:
    return f"pkgs/by-name/{package}/pin.json"


def allowed_paths(pin: Pin) -> Result[frozenset[str], str]:
    """The files the realizer may change: the pin and each companion's path."""
    paths = {pin_path(pin.name)}
    own_dir = PurePosixPath(f"pkgs/by-name/{pin.name}")
    for companion in pin.companions:
        p = PurePosixPath(companion.path)
        if p.is_absolute() or ".." in p.parts or str(p) != companion.path:
            return Error(f"companion path {companion.path!r} is not a normalized repository-relative path")
        if p.is_relative_to(own_dir):
            return Error(f"companion path {companion.path!r} lies inside {own_dir}")
        if p.suffix == ".nix":
            return Error(f"companion path {companion.path!r} names a Nix file")
        paths.add(companion.path)
    return Ok(frozenset(paths))


def source_url(source: Source) -> str:
    match source:
        case GithubRelease(owner=owner, repo=repo):
            return f"https://github.com/{owner}/{repo}"
        case GitCommit(owner=owner, repo=repo):
            return f"https://github.com/{owner}/{repo}"
        case Npm(package=package):
            return f"https://registry.npmjs.org/{package}"
        case Pypi(package=package):
            return f"https://pypi.org/pypi/{package}/json"
        case VendorJson(url=url):
            return url
        case VendorText(url=url):
            return url


def _asset_urls(asset: PlanAsset) -> tuple[str, ...]:
    match asset.checksum:
        case PlanUpstreamFile(url=url):
            return (asset.url, url)
        case Prefetch():
            return (asset.url,)


def plan_urls(plan: Plan) -> tuple[str, ...]:
    urls: list[str] = []
    for artifact in plan.artifacts.values():
        match artifact:
            case PlanPlatformBinaries(platforms=platforms):
                for platform in platforms.values():
                    urls.extend(_asset_urls(platform))
            case PlanFile(asset=asset):
                urls.extend(_asset_urls(asset))
            case PlanFetchFromGitHub() | PlanDerived():
                pass
            case PlanFileValue(url=url):
                urls.append(url)
            case PlanRuntimeFetch(probe_url=url):
                urls.append(url)
    return tuple(urls)


def host_of(url: str) -> str:
    return (urlsplit(url).hostname or "").lower()


def allowed_hosts(pin: Pin, plan: Plan) -> frozenset[str]:
    """Hosts named by the evaluated plan and the source, never a forge API host."""
    hosts = {host_of(u) for u in (*plan_urls(plan), source_url(pin.source))}
    return frozenset(hosts - FORGE_API_HOSTS - {""})


def check_url(url: str, hosts: frozenset[str]) -> Result[None, str]:
    parts = urlsplit(url)
    if parts.scheme != "https":
        return Error(f"refused {url}: not https")
    host = host_of(url)
    if host in FORGE_API_HOSTS:
        return Error(f"refused {url}: forge API host")
    if host not in hosts:
        return Error(f"refused {url}: host {host} is named by neither the plan nor the source")
    return Ok(None)


@dataclass
class PolicyHttp(Http):
    """An `Http` that sends only GET and HEAD, only to `hosts`, and caches bodies."""

    inner: Http
    hosts: frozenset[str]
    _cache: dict[tuple[Method, str], bytes] = field(default_factory=lambda: {})

    @override
    def request(self, method: Method, url: str, timeout: float) -> Result[bytes, str]:
        if method not in ("GET", "HEAD"):
            return Error(f"refused {method} {url}: only GET and HEAD are sent")
        checked = check_url(url, self.hosts)
        if checked.is_error():
            return Error(checked.error)
        key = (method, url)
        if key in self._cache:
            return Ok(self._cache[key])
        body = self.inner.request(method, url, timeout)
        if body.is_ok():
            self._cache[key] = body.ok
        return body
