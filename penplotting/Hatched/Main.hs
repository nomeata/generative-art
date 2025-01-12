{-# LANGUAGE TupleSections #-}
module Main (main) where

import Draw.Plotting
import Draw
import Geometry
import qualified Geometry.Shapes as Shapes (haskellLogo)
import Data.List (sortOn)
import qualified Data.Text.Lazy.IO as T

-- DIN A4
_picWidth, picHeight :: Double
_picWidth = 297
picHeight = 210

haskellLogo :: [Polygon]
haskellLogo = transform (translate (Vec2 15 10) <> scale (picHeight - 20) <> mirrorAlong (angledLine (Vec2 0 0.5) (deg 0) 1)) Shapes.haskellLogo

main :: IO ()
main = do
    let hatches = fmap (\poly -> hatch poly zero 1) haskellLogo
        hatchesWithPressure = concat $ zipWith (\p hs -> fmap (, p) hs) [2, 5, 10, 10] hatches
        sortedHatches = sortOn (\(Line (Vec2 _ y) _, _) -> y) $ sortOn (\(Line (Vec2 x _) _, _) -> x) hatchesWithPressure
        settings = def { _feedrate = 30000, _zTravelHeight = 1 }
        plotResult = runPlot settings $ for_ sortedHatches $ \(Line p q, pressure) -> do
            withDrawingHeight (-pressure) $ do
                repositionTo p
                lineTo q
    T.putStrLn (renderGCode (_plotGCode plotResult))
