{-# LANGUAGE TypeFamilies #-}

-- | Type classes for Toil abstraction.
-- * MonadUtxoRead and MonadUtxo for encapsulation of Utxo storage.
-- * MonadBalancesRead and MonadBalances for encapsulation of Balances storage.
-- * MonadTxPoll for encapsulation of mem pool of local transactions.

module Pos.Txp.Toil.Class
       ( MonadUtxoRead (..)
       , utxoGetReader
       , MonadUtxo (..)
       , MonadBalancesRead (..)
       , MonadBalances (..)
       , MonadTxPool (..)
       ) where

import           Universum

import           Control.Lens               (at, (.=))
import           Control.Monad.Trans.Class  (MonadTrans)
import qualified Ether
import           Serokell.Data.Memory.Units (Byte)

import           Pos.Core                   (Coin, StakeholderId)
import           Pos.Txp.Core.Types         (TxAux, TxId, TxIn, TxOutAux, TxUndo)
import           Pos.Txp.Toil.Types         (Utxo)
import           Pos.Util.Util              (HasLens', ether, lensOf)

----------------------------------------------------------------------------
-- MonadUtxo
----------------------------------------------------------------------------

class Monad m => MonadUtxoRead m where
    utxoGet :: TxIn -> m (Maybe TxOutAux)
    default utxoGet :: (MonadTrans t, MonadUtxoRead m', t m' ~ m) => TxIn -> m (Maybe TxOutAux)
    utxoGet = lift . utxoGet
    getFullUtxo :: m (HashMap TxIn TxOutAux)

instance {-# OVERLAPPABLE #-}
    (MonadUtxoRead m, MonadTrans t, Monad (t m)) =>
        MonadUtxoRead (t m)
  where
    getFullUtxo = lift getFullUtxo

-- | Implementation of 'utxoGet' which takes data from 'MonadReader' context.
utxoGetReader :: (HasLens' ctx Utxo, MonadReader ctx m) => TxIn -> m (Maybe TxOutAux)
utxoGetReader txIn = view $ lensOf @Utxo . at txIn

instance MonadUtxoRead ((->) Utxo) where
    utxoGet = utxoGetReader

instance Monad m => MonadUtxoRead (Ether.StateT' Utxo m) where
    utxoGet id = ether $ use (at id)

class MonadUtxoRead m => MonadUtxo m where
    utxoPut :: TxIn -> TxOutAux -> m ()
    default utxoPut :: (MonadTrans t, MonadUtxo m', t m' ~ m) => TxIn -> TxOutAux -> m ()
    utxoPut a = lift . utxoPut a
    utxoDel :: TxIn -> m ()
    default utxoDel :: (MonadTrans t, MonadUtxo m', t m' ~ m) => TxIn -> m ()
    utxoDel = lift . utxoDel

instance {-# OVERLAPPABLE #-}
  (MonadUtxo m, MonadTrans t, Monad (t m)) => MonadUtxo (t m)

instance Monad m => MonadUtxo (Ether.StateT' Utxo m) where
    utxoPut id v = ether $ at id .= Just v
    utxoDel id = ether $ at id .= Nothing

----------------------------------------------------------------------------
-- MonadBalances
----------------------------------------------------------------------------

class Monad m => MonadBalancesRead m where
    getStake :: StakeholderId -> m (Maybe Coin)
    getTotalStake :: m Coin

    default getStake
        :: (MonadTrans t, MonadBalancesRead m', t m' ~ m) => StakeholderId -> m (Maybe Coin)
    getStake = lift . getStake

    default getTotalStake
        :: (MonadTrans t, MonadBalancesRead m', t m' ~ m) => m Coin
    getTotalStake = lift getTotalStake

instance {-# OVERLAPPABLE #-}
    (MonadBalancesRead m, MonadTrans t, Monad (t m)) =>
        MonadBalancesRead (t m)

class MonadBalancesRead m => MonadBalances m where
    setStake :: StakeholderId -> Coin -> m ()
    setTotalStake :: Coin -> m ()

    default setStake
        :: (MonadTrans t, MonadBalances m', t m' ~ m) => StakeholderId -> Coin -> m ()
    setStake id = lift . setStake id

    default setTotalStake
        :: (MonadTrans t, MonadBalances m', t m' ~ m) => Coin -> m ()
    setTotalStake = lift . setTotalStake

instance {-# OVERLAPPABLE #-}
    (MonadBalances m, MonadTrans t, Monad (t m)) =>
        MonadBalances (t m)

----------------------------------------------------------------------------
-- MonadTxPool
----------------------------------------------------------------------------

class Monad m => MonadTxPool m where
    -- | Check whether Tx with given identifier is stored in the pool.
    hasTx :: TxId -> m Bool
    -- | Return size of the pool's binary representation (approximate).
    poolSize :: m Byte
    -- | Put a transaction with corresponding Undo into MemPool.
    -- Transaction must not be in MemPool.
    putTxWithUndo :: TxId -> TxAux -> TxUndo -> m ()

    default hasTx
        :: (MonadTrans t, MonadTxPool m', t m' ~ m) => TxId -> m Bool
    hasTx = lift . hasTx

    default poolSize
        :: (MonadTrans t, MonadTxPool m', t m' ~ m) => m Byte
    poolSize = lift poolSize

    default putTxWithUndo
        :: (MonadTrans t, MonadTxPool m', t m' ~ m) => TxId -> TxAux -> TxUndo -> m ()
    putTxWithUndo id tx = lift . putTxWithUndo id tx

instance {-# OVERLAPPABLE #-}
    (MonadTxPool m, MonadTrans t, Monad (t m)) =>
        MonadTxPool (t m)
