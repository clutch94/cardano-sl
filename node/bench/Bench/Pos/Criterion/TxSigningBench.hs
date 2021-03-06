module Bench.Pos.Criterion.TxSigningBench
       ( runBenchmark
       ) where

import           Criterion.Main           (Benchmark, bench, defaultConfig,
                                           defaultMainWith, env, whnf)
import           Criterion.Types          (Config (..))
import           Test.QuickCheck          (generate)
import           Universum

import           Pos.Arbitrary.Txp.Unsafe ()
import           Pos.Crypto               (SecretKey, SignTag (SignTx), sign)
import           Pos.Ssc.GodTossing       ()
import           Pos.Txp                  (TxId, TxSig, TxSigData (..))
import           Pos.Util                 (arbitraryUnsafe)

signTx :: (SecretKey, TxId) -> TxSig
signTx (sk, thash) = sign SignTx sk txSigData
  where
    txSigData = TxSigData
        { txSigTxHash = thash
        }

txSignBench :: Benchmark
txSignBench = env genArgs $ bench "Transactions signing" . whnf signTx
  where genArgs = generate $ (,)
                  <$> arbitraryUnsafe
                  <*> arbitraryUnsafe

txSignConfig :: Config
txSignConfig = defaultConfig
    { reportFile = Just "txSigning.html"
    }

runBenchmark :: IO ()
runBenchmark = defaultMainWith txSignConfig [txSignBench]
