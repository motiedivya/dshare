from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("dshare-cli")
except PackageNotFoundError:  # local checkout without installed package metadata
    __version__ = "0+unknown"
