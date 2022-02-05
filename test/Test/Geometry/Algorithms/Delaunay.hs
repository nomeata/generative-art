{-# LANGUAGE RecordWildCards #-}
module Test.Geometry.Algorithms.Delaunay (tests) where

import Control.Monad.IO.Class (MonadIO(liftIO))
import Data.List (scanl')
import qualified Graphics.Rendering.Cairo as Cairo
import System.Random.MWC (create)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase)
import Test.Common (renderAllFormats)

import Geometry.Algorithms.Delaunay
import Geometry.Algorithms.Delaunay.Internal
import Draw
import Geometry
import Geometry.Algorithms.Sampling
import Geometry.Algorithms.Voronoi

tests :: TestTree
tests = testGroup "Delaunay triangulation"
    [ testRandomTriangulation
    , testConversionToVoronoi
    , testLloydRelaxation
    ]

testRandomTriangulation :: TestTree
testRandomTriangulation = testCase "Random points" test
  where
    test = renderAllFormats 220 220 "docs/voronoi/delaunay_random" $ do
        triangulation <- liftIO $ randomDelaunay 200 200
        Cairo.translate 10 10
        for_ (getPolygons triangulation) $ \poly@(Polygon ps) -> cairoScope $ do
            polygonSketch poly
            setColor $ mathematica97 0
            Cairo.setLineJoin Cairo.LineJoinBevel
            Cairo.stroke
            setColor $ mathematica97 1
            for_ ps $ \p -> do
                circleSketch p 4
                Cairo.fill

testConversionToVoronoi :: TestTree
testConversionToVoronoi = testCase "Conversion to Voronoi" test
  where
    test = renderAllFormats 220 220 "docs/voronoi/delaunay_voronoi" $ do
        triangulation <- liftIO $ randomDelaunay 200 200
        let voronoi = toVoronoi triangulation
        Cairo.translate 10 10
        for_ (getPolygons triangulation) $ \poly@(Polygon ps) -> cairoScope $ do
            polygonSketch poly
            setColor $ mathematica97 0 `withOpacity` 0.25
            Cairo.setLineJoin Cairo.LineJoinBevel
            Cairo.stroke
            setColor $ mathematica97 1
            for_ ps $ \p -> do
                circleSketch p 4
                Cairo.fill
        for_ (cells voronoi) $ \Cell{..} -> do
            setColor $ mathematica97 3
            polygonSketch region
            Cairo.stroke

randomDelaunay :: Int -> Int -> IO DelaunayTriangulation
randomDelaunay width height = do
    gen <- liftIO create
    randomPoints <- liftIO $ poissonDisc PoissonDisc { radius = fromIntegral (width * height) / 1000, k = 4, .. }
    pure $ bowyerWatson (BoundingBox (Vec2 0 0) (Vec2 (fromIntegral width) (fromIntegral height))) randomPoints

testLloydRelaxation :: TestTree
testLloydRelaxation = testCase "Lloyd relaxation" test
  where
    test = renderAllFormats 850 220 "docs/voronoi/lloyd_relaxation" $ do
        points <- liftIO $ do
            gen <- create
            uniformlyDistributedPoints gen 200 200 15
        let triangulation0 = bowyerWatson (BoundingBox (Vec2 0 0) (Vec2 200 200)) points
            triangulations = scanl' (flip ($)) triangulation0 (replicate 3 lloydRelaxation)
        Cairo.translate 10 10
        for_ triangulations $ \triangulation -> do
            for_ (cells (toVoronoi triangulation)) $ \Cell{..} -> cairoScope $ do
                setColor $ mathematica97 0
                polygonSketch region
                Cairo.stroke
                setColor $ mathematica97 3
                arrowSketch (Line seed (centroid region)) def { arrowheadSize = 4 }
                Cairo.stroke
                setColor $ mathematica97 1
                circleSketch seed 4
                Cairo.fill
            Cairo.translate 210 0