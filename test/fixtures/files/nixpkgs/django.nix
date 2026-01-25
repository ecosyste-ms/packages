{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pythonOlder,
  asgiref,
  sqlparse,
  argon2-cffi,
  bcrypt,
}:

buildPythonPackage rec {
  pname = "django";
  version = "5.1.4";
  format = "pyproject";

  disabled = pythonOlder "3.10";

  src = fetchFromGitHub {
    owner = "django";
    repo = "django";
    rev = "refs/tags/v${version}";
    hash = "sha256-example123";
  };

  propagatedBuildInputs = [
    asgiref
    sqlparse
  ];

  optional-dependencies = {
    argon2 = [ argon2-cffi ];
    bcrypt = [ bcrypt ];
  };

  meta = with lib; {
    description = "A high-level Python Web framework";
    homepage = "https://www.djangoproject.com/";
    license = licenses.bsd3;
  };
}
