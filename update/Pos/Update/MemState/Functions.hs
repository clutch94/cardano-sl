-- | Functions which work with MemVar.

module Pos.Update.MemState.Functions
       ( withUSLock
       , addToMemPool
       ) where

import           Universum

import           Control.Monad.Catch       (MonadMask)
import qualified Data.HashMap.Strict       as HM

import           Pos.Binary.Class          (biSize)
import           Pos.Binary.Update         ()
import           Pos.Crypto                (PublicKey, hash)
import           Pos.StateLock             (Priority (..), StateLock
                                           , withStateLockNoMetrics)
import           Pos.Update.Core.Types     (LocalVotes, UpdatePayload (..),
                                            UpdateVote (..))
import           Pos.Update.MemState.Types (MemPool (..))
import           Pos.Util.Util             (HasLens')

type UpdateVotes = HashMap PublicKey UpdateVote

-- | Use a lock to perform operation on in-memory state of update system.
--
-- Currently we are using a single lock for everything, so this
-- function is just an alias for 'withStateLock'.
withUSLock
    :: (MonadReader ctx m, HasLens' ctx StateLock, MonadIO m, MonadMask m)
    => m a -> m a
withUSLock = (withStateLockNoMetrics LowPriority) . const

-- | Add given payload to MemPool. Size is updated assuming that all added
-- data is new (is not in MemPool). This assumption is fine, because
-- duplicated data should be considered invalid anyway.
addToMemPool :: UpdatePayload -> MemPool -> MemPool
addToMemPool UpdatePayload {..} = addProposal . addVotes
  where
    addProposal mp =
        case upProposal of
            Nothing -> mp
            Just up -> mp { mpProposals = HM.insert (hash up) up (mpProposals mp)
                          , mpSize = biSize (hash up) + biSize up + mpSize mp}
    -- Here size update is not accurate, but it shouldn't matter.
    addVotes mp = mp { mpLocalVotes = foldr' forceInsertVote (mpLocalVotes mp) upVotes
                     , mpSize = biSize upVotes + mpSize mp}

    forceInsertVote :: UpdateVote -> LocalVotes -> LocalVotes
    forceInsertVote e@UpdateVote{..} = HM.alter (append e) uvProposalId

    append :: UpdateVote -> Maybe UpdateVotes -> Maybe UpdateVotes
    append e@UpdateVote{..} Nothing        = Just $ HM.singleton uvKey e
    append e@UpdateVote{..} (Just stVotes) = Just $ HM.insert uvKey e stVotes
