module Data.Conduit.Vector
    (
    sourceVector,
    sourceMVector,
    consumeVector,
    consumeMVector,
    takeVector,
    takeMVector,
    thawConduit,
    freezeConduit
    )
where

import Control.Monad.Primitive
import Control.Monad.ST
import Data.Conduit
import qualified Data.Conduit.List as L
import Data.Conduit.Util
import qualified Data.Vector.Generic as V
import qualified Data.Vector.Generic.Mutable as M
import qualified Data.Vector.Fusion.Stream as S
import qualified Data.Vector.Fusion.Stream.Monadic as SM

-- | Use an immutable vector as a source.
sourceVector :: (Monad m, V.Vector v a) => v a -> Source m a
sourceVector vec = sourceState (V.stream vec) f
    where f stream | S.null stream = return StateClosed
                   | otherwise = return $ StateOpen (S.tail stream) (S.head stream)

-- | Use a mutable vector as a source in the ST or IO monad.
sourceMVector :: (PrimMonad m, M.MVector v a)
                 => v (PrimState m) a
                 -> Source m a
sourceMVector vec = sourceState (M.mstream vec) f
    where f stream = do isNull <- SM.null stream 
                        if isNull
                            then return StateClosed
                            else do x <- SM.head stream
                                    return $ StateOpen (SM.tail stream) x

-- | Consumes all values from the stream and return as an immutable vector.
-- Due to the way it operates, it requires the ST monad at the minimum,
-- although it can also operate IO. This is due to its dependency on
-- a mutable vector.
consumeVector :: (PrimMonad m, V.Vector v a)
                 => Sink a m (v a)
consumeVector = sinkState (Nothing, 0) push close
    where push (v, index) x = do v' <- case v of
                                        Nothing -> M.new 10
                                        Just vec -> return vec
                                 let len = M.length v'
                                 v'' <- if index >= len
                                            then M.grow v' len
                                            else return v'
                                 M.write v'' index x
                                 return $ StateProcessing (Just v'', index + 1)
          close (Nothing, index) = return $ V.fromList []
          close (Just v, index) = V.unsafeFreeze $ M.take index v

-- | Consumes the first n values from a source and returns as an immutable
-- vector.
takeVector :: (PrimMonad m, V.Vector v a)
              => Int -> Sink a m (v a)
takeVector n = sinkState (Nothing, 0) push close
    where push (v, index) x = do
            v' <- case v of
                    Nothing -> M.new n
                    Just vec -> return vec
            if index >= n
                then do v'' <- V.unsafeFreeze v'
                        return $ StateDone Nothing v''
                else do M.write v' index x
                        return $ StateProcessing (Just v', index + 1)
          close (Nothing, index) = return $ V.fromList []
          close (Just v, index) = V.unsafeFreeze v

-- | Consumes all values from the stream and returns as a mutable vector.
consumeMVector :: (PrimMonad m, M.MVector v a)
                  => Sink a m (v (PrimState m) a)
consumeMVector = sinkState (Nothing, 0) push close
    where push (v, index) x = do v' <- case v of
                                        Nothing -> M.new 10
                                        Just vec -> return vec
                                 let len = M.length v'
                                 v'' <- if index >= len
                                            then M.grow v' len
                                            else return v'
                                 M.write v'' index x
                                 return $ StateProcessing (Just v'', index + 1)
          close (Nothing, index) = M.new 0
          close (Just v, index) = return $ M.take index v

-- | Consumes the first n values from the stream and returns as a
-- mutable vector.
takeMVector :: (PrimMonad m, M.MVector v a)
               => Int -> Sink a m (v (PrimState m) a)
takeMVector n = sinkState (Nothing, 0) push close
    where push (v, index) x =
            do v' <- case v of
                        Nothing -> M.new n
                        Just vec -> return vec
               if index >= n
                    then return $ StateDone Nothing v'
                    else do M.write v' index x
                            return $ StateProcessing (Just v', index + 1)
          close (Nothing, index) = M.new 0
          close (Just v, index) = return v

-- | Conduit which thaws immutable vectors into mutable vectors
thawConduit :: (PrimMonad m, V.Vector v a)
                => Conduit (v a) m (V.Mutable v (PrimState m) a)
thawConduit = L.mapM V.unsafeThaw

-- | Conduit which freezes mutable vectors into immutable vectors
freezeConduit :: (PrimMonad m, V.Vector v a)
                 => Conduit (V.Mutable v (PrimState m) a) m (v a)
freezeConduit = L.mapM V.unsafeFreeze
