{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Data.Foldable     (Foldable (foldl'), for_)
import Numeric           (showHex)
import Prelude           hiding ((**))
import System.IO.Temp    (withSystemTempDirectory)
import System.Random.MWC (createSystemRandom, uniform)

import qualified Graphics.Rendering.Cairo    as Cairo
import qualified Graphics.UI.Threepenny      as UI
import           Graphics.UI.Threepenny.Core

import Draw
import Geometry
import Sampling
import Voronoi

main :: IO ()
main = withSystemTempDirectory "voronoi-interactive" $ \tmpDir -> UI.startGUI UI.defaultConfig (setup tmpDir)

setup :: FilePath -> Window -> UI ()
setup tmpDir window = do
    let w = 1200
        h = 1200
    gen <- liftIO createSystemRandom

    elemCanvas <- UI.canvas # set UI.width w # set UI.height h # set UI.style [("background", "#eeeeee")]
    btnAddPointsGaussian <- UI.button # set UI.text "Add Gaussian distributed points"
    btnAddPointsUniform <- UI.button # set UI.text "Add uniformly distributed points"
    btnReset <- UI.button # set UI.text "Reset"
    btnSave <- UI.button # set UI.text "Save"
    inputFileName <- UI.input # set UI.type_ "text" # set UI.value "voronoi.svg"

    _ <- getBody window #+
        [ row
            [ element elemCanvas
            , column
                [ element btnAddPointsGaussian
                , element btnAddPointsUniform
                , element btnReset
                , row [element inputFileName, element btnSave]
                ]
            ]
        ]

    let initialState = emptyVoronoi (fromIntegral w) (fromIntegral h)

    eAddPointsGaussian <- do
        (eAddPoints, triggerAddPoints) <- liftIO newEvent
        on UI.click btnAddPointsGaussian $ \() -> liftIO $ do
            points <- gaussianDistributedPoints gen (w, 380) (h, 380) 100
            triggerAddPoints (\voronoi -> foldl' addPoint' voronoi points)
        pure eAddPoints
    eAddPointsUniform <- do
        (eAddPoints, triggerAddPoints) <- liftIO newEvent
        on UI.click btnAddPointsUniform $ \() -> liftIO $ do
            points <- uniformlyDistributedPoints gen w h 100
            triggerAddPoints (\voronoi -> foldl' addPoint' voronoi points)
        pure eAddPoints
    let eAddPointByClicking = (\(x, y) -> flip addPoint' (Vec2 x y)) <$> UI.mousedown elemCanvas
        eReset = const initialState <$ UI.click btnReset
        eVoronoi = concatenate <$> unions [eAddPointsGaussian, eAddPointsUniform, eAddPointByClicking, eReset]

    bVoronoi <- accumB initialState eVoronoi

    onChanges bVoronoi $ \voronoi -> do
        tmpFile <- liftIO $ do
            randomNumber <- uniform gen :: IO Int
            pure (tmpDir ++ "/" ++ showHex (abs randomNumber) ".png")
        liftIO $ withSurfaceAuto tmpFile w h $ \surface -> Cairo.renderWith surface $ for_ (cells voronoi) drawCellCairo
        outFile <- loadFile "image/png" tmpFile
        outImg <- UI.img # set UI.src outFile
        on (UI.domEvent "load") outImg $ \_ -> do
            elemCanvas # UI.clearCanvas
            elemCanvas # UI.drawImage outImg (0, 0)

    on UI.click btnSave $ \() -> do
        fileName <- get UI.value inputFileName
        voronoi <- liftIO $ currentValue bVoronoi
        liftIO $ withSurfaceAuto fileName w h $ \surface -> Cairo.renderWith surface $ for_ (cells voronoi) drawCellCairo

drawCellCairo :: VoronoiCell () -> Cairo.Render ()
drawCellCairo Cell{..} = case region of
    Polygon [] -> pure ()
    poly -> do
        let fillColor = parseHex "#eeeeee"
            lineColor = parseHex "#5d81b4"
        polygonSketch poly
        setColor fillColor
        Cairo.fillPreserve
        setColor lineColor
        Cairo.setLineWidth 1
        Cairo.stroke
        circleSketch seed (Distance 5)
        Cairo.fill

data RGB = RGB { r :: Double, g :: Double, b :: Double }

setColor :: RGB -> Cairo.Render ()
setColor RGB{..} = Cairo.setSourceRGB r g b

parseHex :: String -> RGB
parseHex ['#', r1, r2, g1, g2, b1, b2] = RGB
    { r = read ("0x" ++ [r1, r2]) / 255
    , g = read ("0x" ++ [g1, g2]) / 255
    , b = read ("0x" ++ [b1, b2]) / 255 }
parseHex _ = undefined
