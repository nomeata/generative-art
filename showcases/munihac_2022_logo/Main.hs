module Main (main) where



import qualified Data.Set                 as S
import qualified Data.Vector              as V
import           Graphics.Rendering.Cairo as C hiding (x, y, Glyph)

import Draw                           as D
import Geometry.Coordinates.Hexagonal as Hex

import Circuits.GrowingProcess
import Circuits.ReconstructWires
import Circuits.Render



-- ghcid --command='stack ghci generative-art:lib munihac2022logo --main-is munihac2022logo:exe:munihac2022logo' --test=main --warnings --no-title
main :: IO ()
main = do
    let lambdaScale = 3
        lambdaGeometry = hexLambda lambdaScale

        lambdaCircuits = reconstructWires (circuitProcess lambdaGeometry)
    let mainRender = do
            let cellSize = 8
            cairoScope $ do
                setLineJoin LineJoinBevel
                setLineCap LineCapRound
                -- cartesianCoordinateSystem def
                cairoScope $ do
                    C.translate (20*cellSize) (fromIntegral picHeight/2)
                    setLineWidth 3
                    renderWires purple cellSize (cellSize/2) lambdaCircuits
                cairoScope $ do
                    C.translate (6*cellSize) (fromIntegral picHeight/2 - 13 * cellSize)
                    setLineWidth 6
                    renderMunihacWriting purple (cellSize/1.26)
        picWidth = 780
        picHeight = 380
    render "out/munihac-2022-logo.svg" picWidth picHeight mainRender
    render "out/munihac-2022-logo.png" picWidth picHeight $ do
        cairoScope $ do
            setSourceRGB 1 1 1
            paint
        mainRender

    let oneLineRender = do
            let cellSize = 6
            -- cartesianCoordinateSystem def
            setLineJoin LineJoinBevel
            setLineCap LineCapRound
            C.translate 30 54
            renderMunihacWritingOneLine purple (cellSize/2)
        oneLinePicWidth = 640
        oneLinePicHeight = 60

    render "out/munihac-2022-logo-oneline-thin.svg" oneLinePicWidth oneLinePicHeight $ do
        oneLineRender
    render "out/munihac-2022-logo-oneline-thin.png" oneLinePicWidth oneLinePicHeight $ do
        cairoScope $ do
            setSourceRGB 1 1 1
            paint
        oneLineRender
    render "out/munihac-2022-logo-oneline-thick.svg" oneLinePicWidth oneLinePicHeight $ do
        setLineWidth 4
        oneLineRender
    render "out/munihac-2022-logo-oneline-thick.png" oneLinePicWidth oneLinePicHeight $ do
        setLineWidth 4
        cairoScope $ do
            setSourceRGB 1 1 1
            paint
        oneLineRender

    let faviconRender = do
            let cellSize = 10
                smallerLambdaCircuits = reconstructWires (circuitProcess (hexLambda 2))
            cairoScope $ do
                setLineJoin LineJoinBevel
                setLineCap LineCapRound
                cairoScope $ do
                    C.translate (17*cellSize) 160
                    setLineWidth 5
                    renderWires purple cellSize (cellSize/2) smallerLambdaCircuits
    render "out/munihac-2022-favicon.png" 320 320 faviconRender

newtype Glyph = Glyph [[Hex]]

mapGlyph :: (Hex -> Hex) -> Glyph -> Glyph
mapGlyph f (Glyph wires) = Glyph ((map.map) f wires)

letterM :: Glyph
letterM = Glyph
    [ walkInSteps [id, move UL 8, move UR 2, move R 6, move DR 10] hexZero
    , walkInSteps [move UL 10 . move R 4, move DR 6] hexZero
    ]

letterU :: Glyph
letterU = Glyph
    [ walkInSteps [move UL 10, move DR 10, move R 6, move UR 2, move UL 8] hexZero
    ]

letterN :: Glyph
letterN = Glyph
    [ walkInSteps [id, move UL 8, move UR 2, move R 6, move DR 10] hexZero
    ]

letterI :: Glyph
letterI = Glyph
    [ walkInSteps [id, move UL 10] hexZero
    ]

letterH :: Glyph
letterH = Glyph
    [ walkInSteps [id, move UL 10] hexZero
    , walkInSteps [move UL 5, move R 6] hexZero
    , walkInSteps [move R 8, move UL 10] hexZero
    ]

letterA :: Glyph
letterA = Glyph
    [ walkInSteps [id, move UL 8, move UR 2, move R 6, move DR 10] hexZero
    , walkInSteps [move UL 5, move R 6] hexZero
    ]

letterC :: Glyph
letterC = Glyph
    [ walkInSteps [move R 8, move L 8, move UL 8, move UR 2, move R 6] hexZero
    ]

digit2 :: Glyph
digit2 = Glyph
    [ walkInSteps [move R 7, move L 7, move UL 3, move UR 2, move R 3, move UR 2, move UL 3, move L 5, move DL 1] hexZero
    ]

digit0 :: Glyph
digit0 = Glyph
    [ walkInSteps [id, move R 5, move UR 2, move UL 8, move L 5, move DL 2, move DR 6] hexZero
    ]

muni :: [Glyph]
muni =
    [ letterM
    , mapGlyph (move R 12) letterU
    , mapGlyph (move R 24) letterN
    , mapGlyph (move R 36) letterI
    ]

hac :: [Glyph]
hac =
    [ letterH
    , mapGlyph (move R 12) letterA
    , mapGlyph (move R 24) letterC ]

x2022 :: [Glyph]
x2022 =
    [ digit2
    , mapGlyph (move R 10) digit0
    , mapGlyph (move R 20) digit2
    , mapGlyph (move R 30) digit2
    ]

renderMunihacWriting :: ColorScheme -> Double -> Render ()
renderMunihacWriting colorScheme cellSize = do
    let ColorScheme colors = colorScheme
    cairoScope $ do
        colors V.! 2
        for_ muni $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move DR (0+2) . move R 12) wire)
    cairoScope $ do
        colors V.! 1
        for_ hac $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move DR (14+2) . move R 12) wire)
    cairoScope $ do
        colors V.! 0
        for_ x2022 $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move DR (28+2) . move R 12) wire)

renderMunihacWritingOneLine :: ColorScheme -> Double -> Render ()
renderMunihacWritingOneLine colorScheme cellSize = do
    let ColorScheme colors = colorScheme
    cairoScope $ do
        colors V.! 2
        for_ muni $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move R 0) wire)
    cairoScope $ do
        colors V.! 1
        for_ hac $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move R 40) wire)
    cairoScope $ do
        colors V.! 0
        for_ x2022 $ \(Glyph wires) ->
            for_ wires $ \wire ->
                renderWire
                    cellSize
                    cellSize
                    (map (move R 78) wire)

-- | A lambda in hexagonal coordinates.
hexLambda
    :: Int -- ^ Scale parameter. c*10 will be the total height.
    -> ProcessGeometry
hexLambda c | c <= 0 = ProcessGeometry S.empty S.empty
hexLambda c = ProcessGeometry
    { _inside = pointsOnInside
    , _edge =  pointsOnEdge
    }
  where
    polygon = Hex.Polygon corners
    corners = walkInSteps
        [ id
        , move R  (c*2)
        , move DR (c*10)
        , move L  (c*2)
        , move UL (c*3)
        , move DL (c*3)
        , move L  (c*2)
        , move UR (c*5)
        ]
        (move UL (c*5) (move L c hexZero))

    floodFillStart = hexZero
    floodFilled = floodFill floodFillStart (edgePoints polygon)
    pointsOnInside = floodFilled `S.difference` pointsOnEdge
    pointsOnEdge = edgePoints polygon

walkInSteps :: [hex -> hex] -> hex -> [hex]
walkInSteps [] _pos = []
walkInSteps (f:fs) pos =
    let newPoint = f pos
    in newPoint : walkInSteps fs newPoint
