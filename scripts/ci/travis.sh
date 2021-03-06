#!/usr/bin/env bash

set -e

if [[ ("$TRAVIS_OS_NAME" == "linux") && ("$TRAVIS_BRANCH" == "master") ]];
  then with_haddock=true
  else with_haddock=false
fi

if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
    if [[ "$with_haddock" == "true" ]]; then

      # We need to pass CONFIG=wallet to compile cardano-sl-core, but Stack doesn't
      # support passing arguments to Haddock yet (this will be fixed in the next
      # release after 1.4.0). For now, a workaround is to manually replace CONFIG
      # with "wallet" in *.hs files.
      #
      # When new Stack is released, delete this and add an argument to Stack:
      #    --haddock-arguments="--optghc=-DCONFIG=wallet"
      find core/ -name '*.hs' -exec sed -i 's/defined(CONFIG)/1/g' {} +
      find core/ -name '*.hs' -exec sed -i 's/QUOTED(CONFIG)/"'$DCONFIG'"/g' {} +
    fi

fi

# We need to pass CONFIG=wallet to compile cardano-sl-core, but Stack doesn't
# support passing arguments to Haddock yet (this will be fixed in the next
# release after 1.4.0). For now, a workaround is to manually replace CONFIG
# with "wallet" in *.hs files.
#
# When new Stack is released, delete this and add an argument to Stack:
#    --haddock-arguments="--optghc=-DCONFIG=wallet"
if [[ "$with_haddock" == "true" ]]; then
  find core/ -name '*.hs' -exec sed -i 's/defined(CONFIG)/1/g' {} +
  find core/ -name '*.hs' -exec sed -i 's/QUOTED(CONFIG)/"'$DCONFIG'"/g' {} +
fi

targets="cardano-sl cardano-sl-lwallet cardano-sl-tools cardano-sl-wallet"

# There are no macOS explorer devs atm and it's only deployed on linux
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
   targets="$targets cardano-sl-explorer-static"
fi

# TODO: CSL-1133: Add test coverage to CI. To be reenabled when build times
# become smaller and allow coverage report to be built.
#projects="core db lrc infra update ssc godtossing txp"
#to_build=''

#for prj in $projects; do
#  to_build="$to_build cardano-sl-$prj"
#done

for trgt in $targets; do
  echo building $trgt with nix
  nix-build -A $trgt -o $trgt.root --argstr dconfig $DCONFIG --argstr gitrev $TRAVIS_COMMIT
#    TODO: CSL-1133
#    if [[ "$trgt" == "cardano-sl" ]]; then
#      stack test --nix --fast --jobs=2 --coverage \
#      --ghc-options="-j -DCONFIG=$DCONFIG +RTS -A128m -n2m -RTS";
#      stack --nix hpc report $to_build
#    fi

done

#if [[ "$TRAVIS_OS_NAME" == "linux" && "$TRAVIS_BRANCH" == "master" && "$TRAVIS_PULL_REQUEST" == "false" ]]; then
  #./update-wallet-web-api-docs.sh
  #./update-explorer-web-api-docs.sh
  #./update-cli-docs.sh
  #./update-haddock.sh
#fi

./cardano-sl-wallet.root/bin/cardano-wallet-hs2purs

# Generate daedalus-bridge
pushd daedalus
  nix-shell --run "npm install && npm run build:prod"
  echo $TRAVIS_BUILD_NUMBER > build-id
  cp ../log-config-prod.yaml .
  cp ../cardano-sl-tools.root/bin/cardano-launcher .
  cp ../cardano-sl-wallet.root/bin/cardano-node .
  # check that binaries exit with 0
  ./cardano-node --help > /dev/null
  ./cardano-launcher --help > /dev/null
popd

# Replace TRAVIS_BRANCH slash not to fail on subdirectory missing
export BUILD_UID="$TRAVIS_OS_NAME-${TRAVIS_BRANCH//\//-}"
export XZ_OPT=-1

echo "Packing up daedalus-bridge ..."
tar cJf s3/daedalus-bridge-$BUILD_UID.tar.xz daedalus/
echo "Done"

# For now we dont have macOS developers on explorer
if [[ ("$TRAVIS_OS_NAME" == "linux") ]]; then
  # Generate explorer frontend
  EXPLORER_EXECUTABLE=$(pwd)/cardano-sl-explorer-static.root/bin/cardano-explorer-hs2purs ./explorer/frontend/scripts/build.sh

  echo "Packing up explorer-frontend ..."
  tar cJf s3/explorer-frontend-$BUILD_UID.tar.xz explorer/frontend/dist
  echo "Done"
fi
