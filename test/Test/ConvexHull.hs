module Test.ConvexHull (tests) where



import Data.Default.Class
import Data.Foldable
import Data.List
import Graphics.Rendering.Cairo as Cairo hiding (x, y)
import Control.Monad.ST
import System.Random.MWC               as MWC
import System.Random.MWC.Distributions as MWC
import Control.Monad
import qualified Data.Vector as V
import Data.Function

import Draw
import Geometry
import Geometry.Chaotic

import Test.Common
import Test.Helpers
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck



tests :: TestTree
tests = testGroup "Convex hull"
    [ idempotencyTest
    , allPointsInHullTest
    , convexHullIsConvexTest
    , isNotSelfIntersecting
    , visualTest
    ]

visualTest :: TestTree
visualTest = testCase "Visual" $ do
    let points = runST $ do
            gen <- MWC.initialize (V.fromList [])
            replicateM 128 (fix $ \loop -> do
                v <- Vec2 <$> MWC.normal 0 30 gen <*> MWC.normal 0 30 gen
                if norm v <= 100 then pure v else loop)

        hull = convexHull points

    renderVisual points hull
    assertions points hull
  where
    renderVisual points hull = renderAllFormats 210 180 "docs/geometry/convex_hull" $ do
        Cairo.translate 110 90
        setLineWidth 1
        for_ (polygonEdges hull) $ \edge@(Line start _) -> do
            setColor $ mmaColor 1 1
            arrowSketch edge def{ arrowheadRelPos = 0.5
                                , arrowheadSize   = 5 }
            stroke
            setColor $ mmaColor 3 1
            circleSketch start 2
            fill

        setColor $ mmaColor 1 1
        moveTo 0 85
        setFontSize 12
        showText "Convex hull"

        setColor $ mmaColor 0 0.5
        let Polygon hullPoints = hull
        for_ (points \\ hullPoints) $ \p -> do
            circleSketch p 2
            fill

    assertions points hull =
        assertBool "Some points lie outside the hull!" $
            let notHullPoints = let Polygon hullPoints = hull in points \\ hullPoints
            in all (\p -> pointInPolygon p hull) notHullPoints

idempotencyTest :: TestTree
idempotencyTest = testProperty "Idempotency" (forAll gen prop)
  where
    gen = do
        seed <- arbitrary
        numPoints <- choose (10, 100)
        pure $ runST $ do
            g <- initializeMwc (seed :: Int)
            replicateM numPoints (Vec2 <$> standard g <*> standard g)
    prop points = let Polygon hull  = convexHull points
                      Polygon hull' = convexHull hull
                  in hull === hull'

allPointsInHullTest :: TestTree
allPointsInHullTest
  = testProperty "All points are inside the hull" $
        \(LotsOfGaussianPoints points) ->
            let hull@(Polygon hullPoints) = convexHull points
            in all (\p -> pointInPolygon p hull) (points \\ hullPoints)

convexHullIsConvexTest :: TestTree
convexHullIsConvexTest = testProperty "Convex hull is convex" $
    \(LotsOfGaussianPoints points) -> isConvex (convexHull points)

isNotSelfIntersecting :: TestTree
isNotSelfIntersecting = testProperty "Result is satisfies polygon invariants" $
    \(LotsOfGaussianPoints points) -> case validatePolygon (convexHull points) of
        Left err -> error (show err)
        Right _ -> ()
