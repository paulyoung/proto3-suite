-- | This module provides a safer alternative to the raw 'Data.Protobuf.Wire'
-- library based on 'GHC.Generics'.
--
-- Instead of generating Haskell code from a .proto file, we write our message
-- formats as Haskell types, and generate the serializer. We would also be able
-- to generate the .proto file, but that is not supported yet.
--
-- To use this library, simply derive a 'Generic' instance for your type(s), and
-- use the default `HasEncoding` instance.
--
-- = Field Numbers
--
-- Field numbers are automatically generated by the library, starting at 1.
-- Therefore, adding new fields is a compatible change only at the end of a
-- record. Renaming fields is also safe.
--
-- = Strings
--
-- Use 'TL.Text' instead of 'String' for string types inside messages.
--
-- = Example
-- > data MultipleFields =
-- >   MultipleFields {multiFieldDouble :: Double,
-- >                   multiFieldFloat :: Float,
-- >                   multiFieldInt32 :: Int32,
-- >                   multiFieldInt64 :: Int64,
-- >                   multiFieldString :: TL.Text,
-- >                   multiFieldBool :: Bool}
-- >                   deriving (Show, Generic, Eq)
-- > instance HasEncoding MultipleFields
-- > instance HasDecoding MultipleFields
-- >
-- > serialized = toLazyByteString $ MultipleFields 1.0 1.0 1 1 "hi" True
-- >
-- > deserialized :: MultipleFields
-- > deserialized = case parse parser (toStrict serialized) of
-- >                Left e -> error e
-- >                Right msg -> msg


{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE OverloadedLists #-}

module Data.Protobuf.Wire.Generic
  ( HasEncoding(..)
  , HasDecoding(..)

  -- * Encoding
  , toLazyByteString

  -- * Decoding
  , parser

  -- * Supporting Classes
  , GenericHasEncoding(..)
  , GenericHasDecoding(..)
  ) where

import           Control.Monad
import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import           Data.Int (Int32, Int64)
import           Data.Maybe (maybeToList)
import           Data.Monoid ((<>))
import qualified Data.Vector as V
import           Data.Protobuf.Wire.Encode as Wire
import           Data.Protobuf.Wire.Decode.Parser
import           Data.Protobuf.Wire.Shared as Wire
import           Data.Proxy (Proxy(..))
import           Data.Word (Word32, Word64)
import qualified Data.Text.Lazy as TL
import qualified Data.Text as T
import           GHC.Generics
import           GHC.TypeLits
import           GHC.Exts (fromList)

-- | This class captures those types which can be serialized as protobuf messages.
--
-- Instances are provides for supported primitive types, and instances can be derived
-- for other types.
class HasEncoding a where

  -- | The number of protobuf fields in a message.
  type FieldCount a :: Nat
  type FieldCount a = GenericFieldCount (Rep a)

  -- | Encode a message as a binary protobuf message, starting at the specified 'FieldNumber'.
  encode :: FieldNumber -> a -> BB.Builder
  default encode :: (Generic a, GenericHasEncoding (Rep a)) => FieldNumber -> a -> BB.Builder
  encode num = genericEncode num . from

-- | Serialize a message as a lazy 'BL.ByteString'.
toLazyByteString :: HasEncoding a => a -> BL.ByteString
toLazyByteString = BB.toLazyByteString . encode (fieldNumber 1)

-- | A parser for any message that can be decoded. For use with 'parse'.
parser :: HasDecoding a => Parser a
parser = decode (fieldNumber 1)

instance HasEncoding Int32 where
  type FieldCount Int32 = 1
  encode = int32

instance HasEncoding Int64 where
  type FieldCount Int64 = 1
  encode = int64

instance HasEncoding Word32 where
  type FieldCount Word32 = 1
  encode = uint32

instance HasEncoding Word64 where
  type FieldCount Word64 = 1
  encode = uint64

instance HasEncoding (Signed Int32) where
  type FieldCount (Signed Int32) = 1
  encode num = sint32 num . signed

instance HasEncoding (Signed Int64) where
  type FieldCount (Signed Int64) = 1
  encode num = sint64 num . signed

instance HasEncoding (Fixed Word32) where
  type FieldCount (Fixed Word32) = 1
  encode num = fixed32 num . fixed

instance HasEncoding (Fixed Word64) where
  type FieldCount (Fixed Word64) = 1
  encode num = fixed64 num . fixed

instance HasEncoding (Signed (Fixed Int32)) where
  type FieldCount (Signed (Fixed Int32)) = 1
  encode num = sfixed32 num . fixed . signed

instance HasEncoding (Signed (Fixed Int64)) where
  type FieldCount (Signed (Fixed Int64)) = 1
  encode num = sfixed64 num . fixed . signed

instance HasEncoding Bool where
  type FieldCount Bool = 1
  encode = Wire.enum

instance HasEncoding Float where
  type FieldCount Float = 1
  encode = float

instance HasEncoding Double where
  type FieldCount Double = 1
  encode = double

instance HasEncoding TL.Text where
  type FieldCount TL.Text = 1
  encode = text

instance HasEncoding B.ByteString where
  type FieldCount B.ByteString = 1
  encode = bytes

instance HasEncoding BL.ByteString where
  type FieldCount BL.ByteString = 1
  encode = bytes'

instance Enum e => HasEncoding (Enumerated e) where
  type FieldCount (Enumerated e) = 1
  encode num = Wire.enum num . enumerated

instance HasEncoding a => HasEncoding (Maybe a) where
  type FieldCount (Maybe a) = FieldCount a
  encode fn = encode fn . UnpackedVec . V.fromList . maybeToList

instance HasEncoding a => HasEncoding (UnpackedVec a) where
  type FieldCount (UnpackedVec a) = FieldCount a
  encode fn = foldMap (encode fn)

instance HasEncoding a => HasEncoding (NestedVec a) where
  type FieldCount (NestedVec a) = FieldCount a
  encode fn xs = foldMap (encode fn) $ fmap Nested xs

instance HasEncoding (PackedVec Word32) where
  type FieldCount (PackedVec Word32) = FieldCount Word32
  encode fn = packedVarints fn . fmap fromIntegral

instance HasEncoding (PackedVec Word64) where
  type FieldCount (PackedVec Word64) = FieldCount Word64
  encode fn = packedVarints fn . fmap fromIntegral

instance HasEncoding (PackedVec Int32) where
  type FieldCount (PackedVec Int32) = FieldCount Int32
  encode fn = packedVarints fn . fmap fromIntegral

instance HasEncoding (PackedVec Int64) where
  type FieldCount (PackedVec Int64) = FieldCount Int64
  encode fn = packedVarints fn . fmap fromIntegral

instance HasEncoding (PackedVec (Fixed Word32)) where
  type FieldCount (PackedVec (Fixed Word32)) = FieldCount (Fixed Word32)
  encode fn = packedFixed32s fn . fmap fixed

instance HasEncoding (PackedVec (Fixed Word64)) where
  type FieldCount (PackedVec (Fixed Word64)) = FieldCount (Fixed Word64)
  encode fn = packedFixed64s fn . fmap fixed

instance HasEncoding (PackedVec (Fixed Int32)) where
  type FieldCount (PackedVec (Fixed Int32)) = FieldCount (Fixed Int32)
  encode fn = packedFixed32s fn . fmap (fromIntegral . fixed)

instance HasEncoding (PackedVec (Fixed Int64)) where
  type FieldCount (PackedVec (Fixed Int64)) = FieldCount (Fixed Int64)
  encode fn = packedFixed64s fn . fmap (fromIntegral . fixed)

instance HasEncoding (PackedVec (Signed (Fixed Int32))) where
  type FieldCount (PackedVec (Signed (Fixed Int32)))
        = FieldCount (Signed (Fixed Int32))
  encode fn = packedFixed32s fn . fmap (fromIntegral . fixed . signed)

instance HasEncoding (PackedVec (Signed (Fixed Int64))) where
  type FieldCount (PackedVec (Signed (Fixed Int64)))
        = FieldCount (Signed (Fixed Int64))
  encode fn = packedFixed64s fn . fmap (fromIntegral . fixed . signed)

instance HasEncoding (PackedVec Float) where
  type FieldCount (PackedVec Float) = FieldCount (Float)
  encode fn = packedFloats fn

instance HasEncoding (PackedVec Double) where
  type FieldCount (PackedVec Double) = FieldCount (Double)
  encode fn = packedDoubles fn

instance HasEncoding a => HasEncoding (Nested a) where
  type FieldCount (Nested a) = 1
  encode fn = embedded fn . encode (fieldNumber 1) . nested

class GenericHasEncoding f where
  type GenericFieldCount f :: Nat

  genericEncode :: FieldNumber -> f a -> BB.Builder

instance GenericHasEncoding V1 where
  type GenericFieldCount V1 = 0
  genericEncode _ _ = error "genericEncode: empty type"

instance GenericHasEncoding U1 where
  type GenericFieldCount U1 = 0
  genericEncode _ _ = mempty

-- | Because of the lack of a type-level 'max' operation, we make the
-- somewhat artifical restriction that the first summand should have the most
-- fields.
instance ( KnownNat (GenericFieldCount f)
         , GenericHasEncoding f
         , GenericHasEncoding g
         ) => GenericHasEncoding (f :*: g) where
  type GenericFieldCount (f :*: g) = GenericFieldCount f + GenericFieldCount g
  genericEncode num (x :*: y) = genericEncode num x <> genericEncode (FieldNumber (getFieldNumber num + offset)) y
    where
      offset = fromIntegral $ natVal (Proxy :: Proxy (GenericFieldCount f))

instance ( HasEncoding c
         ) => GenericHasEncoding (K1 i c) where
  type GenericFieldCount (K1 i c) = 1
  genericEncode num (K1 x) = encode num x

instance GenericHasEncoding f => GenericHasEncoding (M1 i t f) where
  type GenericFieldCount (M1 i t f) = GenericFieldCount f
  genericEncode num (M1 x) = genericEncode num x

-- | Class of all types which can be deserialized from protobuf messages.
-- Instances can be derived generically.
class HasDecoding a where
  -- | decode a field given a particular field number. To simply parse an
  -- entire message, see 'parser' and 'parse'.
  decode :: FieldNumber -> Parser a

  default decode :: (Generic a, GenericHasDecoding (Rep a))
                    => FieldNumber -> Parser a
  decode = fmap to . genericDecode

--Huge amounts of boilerplate below to prevent overlapping instance errors.

instance HasDecoding Bool where
  decode = field

instance HasDecoding Int32 where
  decode = field

instance HasDecoding (Signed Int32) where
  decode = field

instance HasDecoding Word32 where
  decode = field

instance HasDecoding Int64 where
  decode = field

instance HasDecoding (Signed Int64) where
  decode = field

instance HasDecoding Word64 where
  decode = field

instance HasDecoding (Fixed Word32) where
  decode = field

instance HasDecoding (Signed (Fixed Int32)) where
  decode = field

instance HasDecoding (Fixed Word64) where
  decode = field

instance HasDecoding (Signed (Fixed Int64)) where
  decode = field

instance HasDecoding Float where
  decode = field

instance HasDecoding Double where
  decode = field

instance HasDecoding TL.Text where
  decode = field

instance HasDecoding T.Text where
  decode = fmap (TL.toStrict) . field

instance HasDecoding B.ByteString where
  decode = field

instance HasDecoding BL.ByteString where
  decode = field

--TODO: this has more constraints than the equivalent HasEncoding. Fixable?
instance (AtomicParsable a, HasDecoding a) => HasDecoding (Maybe a) where
  decode = fmap ((V.!? 0) . unpackedvec) . decode

instance Enum e => HasDecoding (Enumerated e) where
  decode = field

instance AtomicParsable a => HasDecoding (UnpackedVec a) where
  decode = fmap (UnpackedVec . fromList) . repeatedUnpackedList

instance (HasDecoding a, Monoid a)
  => HasDecoding (NestedVec a) where
  decode fn = nestedParser
    where nestedParser = fromList
                         <$> parseEmbeddedList atomicParser fn
          atomicParser = atomicEmbedded (decode (fieldNumber 1))

instance (AtomicParsable a, Packable a)
         => HasDecoding (PackedVec a) where
  decode = fmap (PackedVec . fromList) . repeatedPackedList

instance (Monoid a, HasDecoding a) => HasDecoding (Nested a) where
  decode fn = Nested <$> disembed (decode (FieldNumber 1)) fn

class GenericHasDecoding f where
  genericDecode :: FieldNumber -> Parser (f a)

instance GenericHasDecoding V1 where
  genericDecode _ = error "genericDecode: empty type"

instance GenericHasDecoding U1 where
  genericDecode _ = return U1

instance ( KnownNat (GenericFieldCount f)
         , GenericHasEncoding f
         , GenericHasEncoding g
         , GenericHasDecoding f
         , GenericHasDecoding g
         ) => GenericHasDecoding (f :*: g) where
  genericDecode num = liftM2 (:*:) (genericDecode num) (genericDecode num2)
    where num2 = FieldNumber $ getFieldNumber num + offset
          offset = fromIntegral $ natVal (Proxy :: Proxy (GenericFieldCount f))

instance (HasDecoding c) => GenericHasDecoding (K1 i c) where
  genericDecode = fmap K1 . decode

instance GenericHasDecoding f => GenericHasDecoding (M1 i t f) where
  genericDecode = fmap M1 . genericDecode