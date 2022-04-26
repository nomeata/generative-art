module Main (main) where



import Control.Monad.Primitive
import Control.Monad.Reader.Class
import Control.Monad.ST
import Control.Monad.State.Class
import Data.List (partition)
import qualified Data.Map.Strict          as M
import qualified Data.Set                 as S
import           Data.Traversable
import qualified Data.Vector              as V
import           System.Random.MWC

import Draw
import Draw.Plotting
import Geometry
import Geometry.Algorithms.SimplexNoise
import Geometry.Coordinates.Hexagonal hiding (Polygon, rotateAround)



picWidth, picHeight :: Num a => a
picWidth = 400
picHeight = 400

cellSize :: Num a => a
cellSize = 5

main :: IO ()
main = do
    let prototiles1 a =
            V.fromList $ allRotations =<< [ mkTile [(L, UL, [1..k]), (UR, R, [1..l]), (DR, DL, [1..m])] | k <- [0..3], l <- [0..3], m <- [0..3], k+l+m == max 0 (min 9 (round (9 * a)))]
        prototiles2 a
            = V.fromList $ allRotations =<< concat
                [ [ mkTile [(L, UR, [1..k]), (R, DL, [1..l])] | k <- [0..3], l <- [0..2], k+l == max 0 (min 5 (round (5 * a))) ]
                , [ mkTile [(L, R, [1..k]), (DL, DR, [1..l]), (UL, UR, [1..m])] | k <- [0..3], l <- [0..2], m <- [0..3], k+m <= 5, k+l+m == max 0 (min 7 (round (7 * a))) ]
                ]
        generateTiling prototiles = runST $ do
            gen <- initialize (V.fromList [125])
            noise <- simplex2 def { _simplexFrequency = 1/50, _simplexOctaves = 4 } gen
            let bump d p = case norm p of
                    r | r < d -> exp (1 - 1 / (1 - (r/d)^2))
                      | otherwise -> 0
                variation p = bump (min picHeight picWidth / 2) p ** 0.4 * (1 + 0.1 * (noise p + 1) * 0.5)
            randomTiling (prototiles . variation) gen (hexagonsInRange 25 hexZero)

        settings = def
            { _zTravelHeight = 3
            , _zDrawingHeight = -0.5
            , _feedrate = 1000
            , _previewPenTravelColor = Nothing
            }
    for_ (zip [1..] (generateTiling <$> [prototiles1, prototiles2])) $ \(k, tiling) -> do
        let plotResult = runPlot settings $ do
                let allStrands = strands tiling
                    (strandsColor1, strandsColor2) = partition (\xs -> let (_, (_, i, _)) = V.head xs in i == 2) allStrands
                    optimizationSettings = MinimizePenHoveringSettings
                        { _getStartEndPoint = \arcs -> (fst (arcStartEnd (V.head arcs)), snd (arcStartEnd (V.last arcs)))
                        , _flipObject = Just (fmap reverseArc . V.reverse)
                        , _mergeObjects = Nothing -- Already taken care of in 'strands'
                        }
                    optimize = concatMap V.toList . minimizePenHoveringBy optimizationSettings . S.fromList
                    penChange = withDrawingHeight 0 $ do
                        repositionTo zero
                        penDown
                        pause PauseUserConfirm
                        penUp
                comment "Silver pen"
                local (\s -> s { _previewPenColor = mathematica97 2 }) $
                    for_ (transform (translate (Vec2 (picWidth/2) (picHeight/2))) $ optimize (V.map (uncurry toArc) <$> strandsColor1)) plot
                penChange
                comment "Gold pen"
                local (\s -> s { _previewPenColor = mathematica97 3, _feedrate = 500 }) $ -- gold pen requires veeeery low feedrate
                    for_ (transform (translate (Vec2 (picWidth/2) (picHeight/2))) $ optimize (V.map (uncurry toArc) <$> strandsColor2)) plot
                penChange
        print (_totalBoundingBox plotResult)

        renderPreview ("out/penplotting-truchet" ++ show k ++ "-preview.svg") plotResult
        writeGCodeFile ("truchet" ++ show k ++ ".g") plotResult

newtype Tile = Tile (M.Map (Direction, Int) Direction) deriving (Eq, Ord, Show)

mkTile :: [(Direction, Direction, [Int])] -> Tile
mkTile = Tile . go M.empty
  where
    go :: M.Map (Direction, Int) Direction -> [(Direction, Direction, [Int])] -> M.Map (Direction, Int) Direction
    go m [] = m
    go m ((d1, d2, is) : xs) = foldl' (addArc d1 d2) (go m xs) is
    addArc :: Direction -> Direction -> M.Map (Direction, Int) Direction -> Int -> M.Map (Direction, Int) Direction
    addArc d1 d2 m i = M.insert (d1, arcIndex d1 d2 i) d2 . M.insert (d2, arcIndex d2 d1 i) d1 $ m
    arcIndex d1 d2 i = if cyclic d1 d2 then i else 4-i

cyclic :: Direction -> Direction -> Bool
cyclic d1 d2
    | d1 == reverseDirection d2 = d1 < d2
    | otherwise = (6 + fromEnum d1 - fromEnum d2) `mod` 6 <= 3

extractArc :: Tile -> Maybe ((Direction, Int, Direction), Tile)
extractArc (Tile xs)
    | M.null xs = Nothing
    | otherwise =
        let ((d1, i), d2) = M.findMin xs
        in  Just ((d1, i, d2), deleteArc (Tile xs) (d1, i, d2))

findArc :: Tile -> (Direction, Int) -> Maybe ((Direction, Int, Direction), Tile)
findArc (Tile xs) (d1, i) = fmap (\d2 -> ((d1, i, d2), deleteArc (Tile xs) (d1, i, d2))) (M.lookup (d1, i) xs)

deleteArc :: Tile -> (Direction, Int, Direction) -> Tile
deleteArc (Tile xs) (d1, i, d2) = Tile $ M.delete (d1, i) $ M.delete (d2, 4-i) xs

allRotations :: Tile -> [Tile]
allRotations tile = [ rotateTile i tile | i <- [0..6] ]

rotateTile :: Int -> Tile -> Tile
rotateTile n (Tile xs) = Tile $ M.fromList $ (\((d1, i), d2) -> ((rotateDirection d1, i), rotateDirection d2)) <$> M.toList xs
  where
    rotateDirection d = toEnum ((fromEnum d + n) `mod` 6)

type Tiling = M.Map Hex Tile

randomTiling :: PrimMonad m => (Vec2 -> V.Vector Tile) -> Gen (PrimState m) -> [Hex] -> m Tiling
randomTiling baseTiles gen coords = fmap M.fromList $ for coords $ \hex -> do
    let p = toVec2 cellSize hex
    tile <- randomTile (baseTiles p) gen
    pure (hex, tile)

randomTile :: PrimMonad m => V.Vector Tile -> Gen (PrimState m) -> m Tile
randomTile baseTiles = \gen -> do
    rnd <- uniformRM (0, countTiles - 1) gen
    pure (baseTiles V.! rnd)
  where countTiles = V.length baseTiles

strands :: Tiling -> [V.Vector (Hex, (Direction, Int, Direction))]
strands tiling = case M.lookupMin tiling of
    Nothing -> []
    Just (startHex, t) -> case extractArc t of
        Nothing ->  strands (M.delete startHex tiling)
        Just ((d, i, d'), t') ->
            let tiling' = M.insert startHex t' tiling
                (s, tiling'') = strand tiling' startHex (d, i)
                (s', tiling''') = strand tiling'' startHex (d', 4-i)
            in V.fromList (reverseStrand s ++ [(startHex, (d, i, d'))] ++ s') : strands tiling'''

strand :: Tiling -> Hex -> (Direction, Int) -> ([(Hex, (Direction, Int, Direction))], Tiling)
strand tiling hex (d, i) = let hex' = move d 1 hex in case M.lookup hex' tiling of
    Nothing -> ([], tiling)
    Just t -> case findArc t (reverseDirection d, 4-i) of
        Nothing -> ([], tiling)
        Just ((_, _, d'), t') ->
            let (s', tiling') = strand (M.insert hex' t' tiling) hex' (d', i)
            in  ((hex', (reverseDirection d, 4-i, d')) : s', tiling')

reverseStrand :: [(Hex, (Direction, Int, Direction))] -> [(Hex, (Direction, Int, Direction))]
reverseStrand = fmap (\(h, (d1, i, d2)) -> (h, (d2, 4-i, d1))) . reverse

reverseDirection :: Direction -> Direction
reverseDirection d = toEnum ((fromEnum d + 3) `mod` 6)

data Arc
    = CwArc Vec2 Vec2 Vec2
    | CcwArc Vec2 Vec2 Vec2
    | Straight Vec2 Vec2
    deriving (Eq, Ord, Show)

arcStartEnd :: Arc -> (Vec2, Vec2)
arcStartEnd = \case
    CwArc _ start end -> (start, end)
    CcwArc _ start end -> (start, end)
    Straight start end -> (start, end)

reverseArc :: Arc -> Arc
reverseArc = \case
    CwArc center start end -> CcwArc center end start
    CcwArc center start end -> CwArc center end start
    Straight start end -> Straight end start

cwArc :: Vec2 -> Double -> Angle -> Angle -> Arc
cwArc center radius startAngle endAngle = CwArc center start end
  where
    start = center +. polar startAngle radius
    end = center +. polar endAngle radius

ccwArc :: Vec2 -> Double -> Angle -> Angle -> Arc
ccwArc center radius startAngle endAngle = CcwArc center start end
  where
    start = center +. polar startAngle radius
    end = center +. polar endAngle radius

straight :: Vec2 -> Vec2 -> Arc
straight start end = Straight start end

-- Valid for translation, rotation and aspect-preserving scaling,
-- but breaks down for mirroring and not-aspect-preserving scaling.
instance Transform Arc where
    transform t (CwArc center start end) = CwArc (transform t center) (transform t start) (transform t end)
    transform t (CcwArc center start end) = CcwArc (transform t center) (transform t start) (transform t end)
    transform t (Straight start end) = Straight (transform t start) (transform t end)

instance Sketch Arc where
    sketch (CwArc center start end) = do
        let radius = norm (start -. center)
            startAngle = angleOfLine (Line center start)
            endAngle = angleOfLine (Line center end)
        arcSketchNegative center radius startAngle endAngle
    sketch (CcwArc center start end) = do
        let radius = norm (start -. center)
            startAngle = angleOfLine (Line center start)
            endAngle = angleOfLine (Line center end)
        arcSketch center radius startAngle endAngle
    sketch (Straight start end) = sketch (Line start end)

instance Plotting Arc where
    plot (CwArc center start end) = do
        pos <- gets _penXY
        case norm (pos -. start) of
            0 -> pure ()
            d | d < 0.1 -> lineTo start
            _otherwise -> repositionTo start
        clockwiseArcAroundTo center end
    plot (CcwArc center start end) = do
        pos <- gets _penXY
        case norm (pos -. start) of
            0 -> pure ()
            d | d < 0.1 -> lineTo start
            _otherwise -> repositionTo start
        counterclockwiseArcAroundTo center end
    plot (Straight start end) = do
        pos <- gets _penXY
        case norm (pos -. start) of
            d | d < 0.1 -> lineTo end
            _otherwise -> repositionTo start >> lineTo end


toArc :: Hex -> (Direction, Int, Direction) -> Arc
toArc hex (d1, n, d2) = sketchArc (fromIntegral n') d1 d2
  where
    n' = if cyclic d1 d2 then n else 4-n
    center = toVec2 cellSize hex
    side d = 0.5 *. (center +. nextCenter d)
    nextCenter d = toVec2 cellSize (move d 1 hex)
    corner d d' = (center +. nextCenter d +. nextCenter d') /. 3
    [down, _lowerLeft, _upperLeft, _up, upperRight, lowerRight] = [ transform (rotate alpha) (Vec2 0 cellSize) | alpha <- deg <$> [0, 60 .. 300] ]

    sketchArc i DR UL = straight ((0.5 - 0.25 * i) *. upperRight +. side DR) ((0.5 - 0.25 * i) *. upperRight +. side UL)
    sketchArc i UR DL = straight ((0.5 - 0.25 * i) *. lowerRight +. side UR) ((0.5 - 0.25 * i) *. lowerRight +. side DL)
    sketchArc i R  L  = straight ((0.5 - 0.25 * i) *. down       +. side R)  ((0.5 - 0.25 * i) *. down       +. side L)
    sketchArc i UL DR = straight ((0.5 - 0.25 * i) *. upperRight +. side UL) ((0.5 - 0.25 * i) *. upperRight +. side DR)
    sketchArc i DL UR = straight ((0.5 - 0.25 * i) *. lowerRight +. side DL) ((0.5 - 0.25 * i) *. lowerRight +. side UR)
    sketchArc i L  R  = straight ((0.5 - 0.25 * i) *. down       +. side L)  ((0.5 - 0.25 * i) *. down       +. side R)

    sketchArc i UR L  = ccwArc (nextCenter UL) ((1 + 0.25 * i) * cellSize) (deg 30)  (deg 90)
    sketchArc i R  UL = ccwArc (nextCenter UR) ((1 + 0.25 * i) * cellSize) (deg 90)  (deg 150)
    sketchArc i DR UR = ccwArc (nextCenter R)  ((1 + 0.25 * i) * cellSize) (deg 150) (deg 210)
    sketchArc i DL R  = ccwArc (nextCenter DR) ((1 + 0.25 * i) * cellSize) (deg 210) (deg 270)
    sketchArc i L  DR = ccwArc (nextCenter DL) ((1 + 0.25 * i) * cellSize) (deg 270) (deg 330)
    sketchArc i UL DL = ccwArc (nextCenter L)  ((1 + 0.25 * i) * cellSize) (deg 330) (deg 30)
    sketchArc i L  UR = cwArc (nextCenter UL) ((1 + 0.25 * i) * cellSize) (deg 90)  (deg 30)
    sketchArc i UL R  = cwArc (nextCenter UR) ((1 + 0.25 * i) * cellSize) (deg 150) (deg 90)
    sketchArc i UR DR = cwArc (nextCenter R)  ((1 + 0.25 * i) * cellSize) (deg 210) (deg 150)
    sketchArc i R  DL = cwArc (nextCenter DR) ((1 + 0.25 * i) * cellSize) (deg 270) (deg 210)
    sketchArc i DR L  = cwArc (nextCenter DL) ((1 + 0.25 * i) * cellSize) (deg 330) (deg 270)
    sketchArc i DL UL = cwArc (nextCenter L)  ((1 + 0.25 * i) * cellSize) (deg 30)  (deg 330)

    sketchArc i UL L  = ccwArc (corner L  UL) (0.25 * i * cellSize) (deg 330) (deg 90)
    sketchArc i UR UL = ccwArc (corner UL UR) (0.25 * i * cellSize) (deg 30)  (deg 150)
    sketchArc i R  UR = ccwArc (corner UR R)  (0.25 * i * cellSize) (deg 90)  (deg 210)
    sketchArc i DR R  = ccwArc (corner R  DR) (0.25 * i * cellSize) (deg 150) (deg 270)
    sketchArc i DL DR = ccwArc (corner DR DL) (0.25 * i * cellSize) (deg 210) (deg 330)
    sketchArc i L  DL = ccwArc (corner DL L)  (0.25 * i * cellSize) (deg 270) (deg 30)
    sketchArc i L  UL = cwArc (corner L  UL) (0.25 * i * cellSize) (deg 90)  (deg 330)
    sketchArc i UL UR = cwArc (corner UL UR) (0.25 * i * cellSize) (deg 150) (deg 30)
    sketchArc i UR R  = cwArc (corner UR R)  (0.25 * i * cellSize) (deg 210) (deg 90)
    sketchArc i R  DR = cwArc (corner R  DR) (0.25 * i * cellSize) (deg 270) (deg 150)
    sketchArc i DR DL = cwArc (corner DR DL) (0.25 * i * cellSize) (deg 330) (deg 210)
    sketchArc i DL L  = cwArc (corner DL L)  (0.25 * i * cellSize) (deg 30)  (deg 270)

    sketchArc _ d  d' = error ("Illegal tile " ++ show (d, d'))
