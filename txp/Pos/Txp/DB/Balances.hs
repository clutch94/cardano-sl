{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Part of GState DB which stores stakes.

module Pos.Txp.DB.Balances
       (
         -- * Operations
         BalancesOp (..)

         -- * Getters
       , isBootstrapEra
       , getEffectiveTotalStake
       , getEffectiveStake
       , genesisFakeTotalStake

         -- * Initialization
       , initGStateBalances

         -- * Iteration
       , BalanceIter
       , balanceSource

         -- * Sanity checks
       , sanityCheckBalances
       ) where

import           Control.Monad.Trans.Resource (ResourceT)
import           Data.Conduit                 (Source, mapOutput, runConduitRes, (.|))
import qualified Data.Conduit.List            as CL
import qualified Data.HashMap.Strict          as HM
import qualified Data.Text.Buildable
import qualified Database.RocksDB             as Rocks
import           Formatting                   (bprint, bprint, sformat, (%))
import           Serokell.Util                (Color (Red), colorize)
import           System.Wlog                  (WithLogger, logError)
import           Universum

import           Pos.Binary.Class             (encodeStrict)
import           Pos.Core                     (Coin, StakeholderId, coinF, mkCoin,
                                               sumCoins, unsafeAddCoin,
                                               unsafeIntegerToCoin)
import           Pos.Core.Genesis             (genesisBalances)
import           Pos.Crypto                   (shortHashF)
import           Pos.DB                       (DBError (..), DBTag (GStateDB), IterType,
                                               MonadDB, MonadDBRead, RocksBatchOp (..),
                                               dbIterSource)
import           Pos.DB.GState.Balances       (BalanceIter, ftsStakeKey, ftsSumKey,
                                               getRealStake, getRealTotalStake)
import           Pos.DB.GState.Common         (gsPutBi)
import           Pos.Txp.Core                 (txOutStake)
import           Pos.Txp.Toil.Types           (Utxo)
import           Pos.Txp.Toil.Utxo            (utxoToStakes)
import           Pos.Update.DB                (isBootstrapEra)

----------------------------------------------------------------------------
-- Operations
----------------------------------------------------------------------------

data BalancesOp
    = PutFtsSum !Coin
    | PutFtsStake !StakeholderId
                  !Coin

instance Buildable BalancesOp where
    build (PutFtsSum c) = bprint ("PutFtsSum ("%coinF%")") c
    build (PutFtsStake ad c) =
        bprint ("PutFtsStake ("%shortHashF%", "%coinF%")") ad c

instance RocksBatchOp BalancesOp where
    toBatchOp (PutFtsSum c)      = [Rocks.Put ftsSumKey (encodeStrict c)]
    toBatchOp (PutFtsStake ad c) =
        if c == mkCoin 0 then [Rocks.Del (ftsStakeKey ad)]
        else [Rocks.Put (ftsStakeKey ad) (encodeStrict c)]

----------------------------------------------------------------------------
-- Overloaded getters (for fixed balances for bootstrap era)
----------------------------------------------------------------------------

genesisFakeTotalStake :: Coin
genesisFakeTotalStake = unsafeIntegerToCoin $ sumCoins genesisBalances

getEffectiveTotalStake :: MonadDBRead m => m Coin
getEffectiveTotalStake = ifM isBootstrapEra
    (pure genesisFakeTotalStake)
    getRealTotalStake

getEffectiveStake :: MonadDBRead m => StakeholderId -> m (Maybe Coin)
getEffectiveStake id = ifM isBootstrapEra
    (pure $ HM.lookup id genesisBalances)
    (getRealStake id)

----------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------

initGStateBalances
    :: forall m.
       MonadDB m
    => Utxo -> m ()
initGStateBalances genesisUtxo = do
    putFtsStakes
    putGenesisTotalStake
  where
    putTotalFtsStake = gsPutBi ftsSumKey
    totalCoins = sumCoins $ map snd $ concatMap txOutStake $ toList genesisUtxo
    -- Will 'error' if the result doesn't fit into 'Coin' (which should never
    -- happen)
    putGenesisTotalStake = putTotalFtsStake (unsafeIntegerToCoin totalCoins)
    putFtsStakes = mapM_ (uncurry putFtsStake) . HM.toList $ utxoToStakes genesisUtxo

----------------------------------------------------------------------------
-- Balance
----------------------------------------------------------------------------

-- | Run iterator over effective balances.
balanceSource
    :: forall m . (MonadDBRead m)
    => Source (ResourceT m) (IterType BalanceIter)
balanceSource =
    ifM (lift isBootstrapEra)
        (CL.sourceList $ HM.toList genesisBalances)
        (dbIterSource GStateDB (Proxy @BalanceIter))

----------------------------------------------------------------------------
-- Sanity checks
----------------------------------------------------------------------------

sanityCheckBalances
    :: (MonadDBRead m, WithLogger m)
    => m ()
sanityCheckBalances = do
    calculatedTotalStake <- runConduitRes $
        mapOutput snd (dbIterSource GStateDB (Proxy @BalanceIter)) .|
        CL.fold unsafeAddCoin (mkCoin 0)

    totalStake <- getRealTotalStake
    let fmt = ("Wrong real total stake: \
              \sum of real stakes: "%coinF%
              ", but getRealTotalStake returned: "%coinF)
    let msg = sformat fmt calculatedTotalStake totalStake
    unless (calculatedTotalStake == totalStake) $ do
        logError $ colorize Red msg
        throwM $ DBMalformed msg

----------------------------------------------------------------------------
-- Details
----------------------------------------------------------------------------

putFtsStake :: MonadDB m => StakeholderId -> Coin -> m ()
putFtsStake = gsPutBi . ftsStakeKey
