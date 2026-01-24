{
  lib,
  stdenv,
  brotlicffi,
  buildPythonPackage,
  certifi,
  chardet,
  charset-normalizer,
  fetchPypi,
  idna,
  pysocks,
  pytest-mock,
  pytest-xdist,
  pytestCheckHook,
  pythonOlder,
  urllib3,
}:

buildPythonPackage rec {
  pname = "requests";
  version = "2.32.3";
  format = "setuptools";

  disabled = pythonOlder "3.7";

  __darwinAllowLocalNetworking = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-VTZUF3NOsYJVWQqf+euX6eHaho1MzWQCOZ6vaK8gp2A=";
  };

  propagatedBuildInputs = [
    brotlicffi
    certifi
    charset-normalizer
    idna
    urllib3
  ];

  optional-dependencies = {
    security = [ ];
    socks = [ pysocks ];
    use_chardet_on_py3 = [ chardet ];
  };

  meta = with lib; {
    description = "Python HTTP for Humans";
    homepage = "https://requests.readthedocs.io/";
    license = licenses.asl20;
  };
}
