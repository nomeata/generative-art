{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}

module Draw.GCode (
      renderGCode
    , PlottingSettings(..)
    , draw
    , ToGCode(..)
    , GCode(..)

    -- * Utilities
    , minimizePenHovering
) where



import           Data.Foldable
import qualified Data.Set       as S
import qualified Data.Text.Lazy as TL
import           Data.Vector    (Vector)
import qualified Data.Vector    as V
import           Formatting     hiding (center)

import Geometry.Bezier
import Geometry.Core
import Geometry.Shapes



decimal :: Format r (Double -> r)
decimal = fixed 3

data PlottingSettings = PlottingSettings
    { _previewBoundingBox :: Maybe BoundingBox -- ^ Trace this bounding box to preview extents of the plot and wait for confirmation
    , _feedrate :: Maybe Double -- ^ Either set a feedrate, or have an initial check whether one was set previously
    } deriving (Eq, Ord, Show)

draw :: GCode -> GCode
draw content = flatten $ GBlock
    [ G00_LinearRapidMove Nothing Nothing (Just (-1))
    , content
    , G00_LinearRapidMove Nothing Nothing (Just 1)
    ]

data GCode
    = GComment TL.Text
    | GBlock [GCode]
    | F_Feedrate Double
    | M0_Pause

    | G00_LinearRapidMove (Maybe Double) (Maybe Double) (Maybe Double) -- ^ G0 X Y Z
    | G01_LinearFeedrateMove (Maybe Double) (Maybe Double) (Maybe Double) -- ^ G1 X Y Z
    | G02_ArcClockwise Double Double Double Double -- ^ G02 I J X Y
    | G03_ArcCounterClockwise Double Double Double Double -- ^ G03 I J X Y
    | G90_AbsoluteMovement
    | G91_RelativeMovement

-- | Flatten one level of GCode blocks
flatten :: GCode -> GCode
flatten (GBlock gcodes) = GBlock $ do
    gcode <- gcodes
    case gcode of
        GBlock gcodes' -> gcodes'
        other -> [other]
flatten notABlock = notABlock

addHeaderFooter :: PlottingSettings -> GCode -> GCode
addHeaderFooter settings body = GBlock [header, body, footer]
  where
    feedrateCheck = GBlock $ case _feedrate settings of
        Just f ->
            [ GComment "Initial feedrate"
            , F_Feedrate f
            ]
        Nothing ->
            [ GComment "NOOP move to make sure feedrate is already set externally"
            , G91_RelativeMovement
            , G01_LinearFeedrateMove (Just 0) (Just 0) (Just 0)
            , G90_AbsoluteMovement
            ]

    previewBoundingBox = GBlock $ case _previewBoundingBox settings of
        Just bb ->
            [ GComment "Preview bounding box"
            , toGCode bb
            , M0_Pause
            ]
        Nothing -> []

    header = flatten $ GBlock
        [ GComment "Header"
        , feedrateCheck
        , previewBoundingBox
        ]

    footer = GBlock
        [ GComment "Footer"
        , GComment "Lift pen"
        , G00_LinearRapidMove Nothing Nothing (Just 10)
        ]

renderGCode :: PlottingSettings -> GCode -> TL.Text
renderGCode settings
    = renderGcodeIndented (-1) -- We start at -1 so the first layer GBLock is not indented. Hacky but simple.
    . addHeaderFooter settings

renderGcodeIndented :: Int -> GCode -> TL.Text
renderGcodeIndented !level = \case
    GComment comment -> indent ("; " <> comment)
    GBlock content   -> TL.intercalate "\n" (map (renderGcodeIndented (level+1)) content)
    F_Feedrate f     -> indent (format ("F " % decimal) f)
    M0_Pause         -> indent "M0 ; Pause/wait for user input"

    G00_LinearRapidMove Nothing Nothing Nothing -> mempty
    G00_LinearRapidMove x y z                   -> indent (format ("G0" % optioned (" X"%decimal) % optioned (" Y"%decimal) % optioned (" Z"%decimal)) x y z)

    G01_LinearFeedrateMove Nothing Nothing Nothing -> mempty
    G01_LinearFeedrateMove x y z                   -> indent (format ("G1" % optioned (" X"%decimal) % optioned (" Y"%decimal) % optioned (" Z"%decimal)) x y z)

    G02_ArcClockwise        i j x y -> indent (format ("G2 X" % decimal % " Y" % decimal % " I" % decimal % " J" % decimal) x y i j)
    G03_ArcCounterClockwise i j x y -> indent (format ("G3 X" % decimal % " Y" % decimal % " I" % decimal % " J" % decimal) x y i j)

    G90_AbsoluteMovement -> indent "G90"
    G91_RelativeMovement -> indent "G91"
  where
    indentation = "    "
    indent x = TL.replicate (fromIntegral level) indentation <> x

class ToGCode a where
    toGCode :: a -> GCode

instance ToGCode GCode where
    toGCode = id

-- | Trace the bounding box without actually drawing anything to estimate result size
instance ToGCode BoundingBox where
    toGCode (BoundingBox (Vec2 xMin yMin) (Vec2 xMax yMax)) = GBlock
        [ GComment "Hover over bounding box"
        , G00_LinearRapidMove (Just xMin) (Just yMin) Nothing
        , G00_LinearRapidMove (Just xMax) (Just yMin) Nothing
        , G00_LinearRapidMove (Just xMax) (Just yMax) Nothing
        , G00_LinearRapidMove (Just xMin) (Just yMax) Nothing
        , G00_LinearRapidMove (Just xMin) (Just yMin) Nothing
        ]

instance ToGCode Line where
    toGCode (Line (Vec2 a b) (Vec2 x y)) =
        GBlock
            [ GComment "Line"
            , G00_LinearRapidMove (Just a) (Just b) Nothing
            , draw (G01_LinearFeedrateMove (Just x) (Just y) Nothing)
            ]

instance ToGCode Circle where
    toGCode (Circle (Vec2 x y) r) =
        let (startX, startY) = (x-r, y)
        in GBlock
            [ GComment "Circle"
            , G00_LinearRapidMove (Just startX) (Just startY) Nothing
            , draw (G02_ArcClockwise r 0 startX startY)
            ]

-- | Approximation by a number of points
instance ToGCode Ellipse where
    toGCode (Ellipse trafo) = GBlock
        [ GComment "Ellipse"
        , toGCode (transform trafo (regularPolygon 64))
        ]

-- | Polyline
instance {-# OVERLAPPING #-} Sequential f => ToGCode (f Vec2) where
    toGCode = go . toList
      where
        go [] = GBlock []
        go (Vec2 startX startY : points) = GBlock
            [ GComment "Polyline"
            , G00_LinearRapidMove (Just startX) (Just startY) Nothing
            , draw (GBlock [ G01_LinearFeedrateMove (Just x) (Just y) Nothing | Vec2 x y <- points])
            ]

-- | Draw each element separately. Note the overlap with the Polyline instance, which takes precedence.
instance {-# OVERLAPPABLE #-} (Functor f, Sequential f, ToGCode a) => ToGCode (f a) where
    toGCode x = GBlock (GComment "Sequential" : toList (fmap toGCode x))

-- | Draw each element (in order)
instance {-# OVERLAPPING #-} (ToGCode a, ToGCode b) => ToGCode (a,b) where
    toGCode (a,b) = GBlock [GComment "2-tuple", toGCode a, toGCode b]

-- | Draw each element (in order)
instance {-# OVERLAPPING #-} (ToGCode a, ToGCode b, ToGCode c) => ToGCode (a,b,c) where
    toGCode (a,b,c) = GBlock [GComment "3-tuple", toGCode a, toGCode b, toGCode c]

-- | Draw each element (in order)
instance {-# OVERLAPPING #-} (ToGCode a, ToGCode b, ToGCode c, ToGCode d) => ToGCode (a,b,c,d) where
    toGCode (a,b,c,d) = GBlock [GComment "4-tuple", toGCode a, toGCode b, toGCode c, toGCode d]

-- | Draw each element (in order)
instance {-# OVERLAPPING #-} (ToGCode a, ToGCode b, ToGCode c, ToGCode d, ToGCode e) => ToGCode (a,b,c,d,e) where
    toGCode (a,b,c,d,e) = GBlock [GComment "5-tuple", toGCode a, toGCode b, toGCode c, toGCode d, toGCode e]

instance ToGCode Polygon where
    toGCode (Polygon []) = GBlock []
    toGCode (Polygon (p:ps)) = GBlock -- Like polyline, but closes up the shape
        [ GComment "Polygon"
        , let Vec2 startX startY = p in G00_LinearRapidMove (Just startX) (Just startY) Nothing
        , draw (GBlock [G01_LinearFeedrateMove (Just x) (Just y) Nothing | Vec2 x y <- ps ++ [p]])
        ]

-- | FluidNC doesn’t support G05, so we approximate Bezier curves with line pieces.
-- We use the naive Bezier interpolation 'bezierSubdivideT', because it just so
-- happens to put more points in places with more curvature.
instance ToGCode Bezier where
    toGCode bezier@(Bezier a _ _ _) = GBlock
        [ GComment "Bezier (cubic)"
        , let Vec2 startX startY = a in G00_LinearRapidMove (Just startX) (Just startY) Nothing
        , draw (GBlock [G01_LinearFeedrateMove (Just x) (Just y) Nothing | Vec2 x y <- bezierSubdivideT 32 bezier])
        ]

minimumOn :: (Foldable f, Ord ord) => (a -> ord) -> f a -> Maybe a
minimumOn f xs
    | null xs = Nothing
    | otherwise = Just (minimumBy (\x y -> compare (f x) (f y)) xs)

-- | Sort a collection of polylines so that between each line pair, we only do the shortest move.
-- This is a local solution to what would be TSP if solved globally. Better than nothing I guess,
-- although this algorithm here is \(\mathcal O(n^2)\).
minimizePenHovering :: Sequential vector => S.Set (vector Vec2) -> [Vector Vec2]
minimizePenHovering = mergeStep . sortStep (Vec2 0 0) . S.map toVector
  where
    -- Sort by minimal travel between adjacent lines
    sortStep :: Vec2 -> S.Set (Vector Vec2) -> [Vector Vec2]
    sortStep penPos pool =
        let closestNextLine = minimumOn (\candidate -> norm (V.head candidate -. penPos) `min` norm (V.last candidate -. penPos)) pool
        in case closestNextLine of
            Nothing -> []
            Just l ->
                let rightWayRound = if norm (V.head l -. penPos) > norm (V.last l -. penPos)
                        then V.reverse l
                        else l
                    remainingPool = S.delete l pool
                    newPenPos = V.last rightWayRound
                in rightWayRound : sortStep newPenPos remainingPool

    -- Merge adjacent polylines
    mergeStep :: [Vector Vec2] -> [Vector Vec2]
    mergeStep (t1:t2:rest) = case (V.unsnoc t1, V.uncons t2) of
        (Just (_t1Init, t1Last), Just (t2Head, t2Tail))
            | t1Last == t2Head -> mergeStep (t1 <> t2Tail:rest)
        _ -> t1 : mergeStep (t2:rest)
    mergeStep other = other