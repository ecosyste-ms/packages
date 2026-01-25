{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  libobjc,
  IOKit,
}:

buildGoModule rec {
  pname = "go-ethereum";
  version = "1.14.12";

  src = fetchFromGitHub {
    owner = "ethereum";
    repo = "go-ethereum";
    rev = "v${version}";
    hash = "sha256-example";
  };

  vendorHash = "sha256-vendorhash";

  subPackages = [
    "cmd/abidump"
    "cmd/abigen"
    "cmd/clef"
    "cmd/devp2p"
    "cmd/ethkey"
    "cmd/evm"
    "cmd/geth"
    "cmd/rlpdump"
    "cmd/utils"
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
    libobjc
    IOKit
  ];

  meta = with lib; {
    description = "Official Go implementation of the Ethereum protocol";
    homepage = "https://geth.ethereum.org/";
    license = with licenses; [ lgpl3Plus gpl3Plus ];
  };
}
