module Test.Geometry.Contour (tests) where

import Data.Foldable
import Graphics.Rendering.Cairo as C

import Draw
import Geometry as G
import Geometry.Contour

import Test.Common
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Test.Helpers
import Debug.Trace

tests :: TestTree
tests = testGroup "Contour finding"
    [ findRootOnLineTests
    , fromGridTests
    , valueTableTests
    , applyThresholdTests
    , classifyTests
    , visualTests
    ]

findRootOnLineTests :: TestTree
findRootOnLineTests = testGroup "Narrow down root location on a line"
    [ testCase "Linear function along x axis" $ do
        let line = Line (Vec2 (-1) 0) (Vec2 1 0)
            f (Vec2 x _) = x
            actual = narrowDownToRoot f line 1e-10
            expected = Vec2 0 0
        assertApproxEqual expected actual
    , testCase "Polynomial function along diagonal" $ do
        let line = Line (Vec2 (-1) (-1)) (Vec2 1 1)
            f (Vec2 x y) = (x+1)*y^2
            actual = narrowDownToRoot f line 1e-10
            expected = Vec2 0 0
        assertApproxEqual expected actual
    ]
  where
    assertApproxEqual expected actual =
        let errMsg = unlines
                [ "Expected: " ++ show expected
                , "Actual:   " ++ show actual
                ]
        in assertBool errMsg (expected ~== actual)

fromGridTests :: TestTree
fromGridTests = testGroup "Convert grid coordinates to continuous"
    [ testCase "Start" $ do
        let grid = Grid (Vec2 0 0, Vec2 1 1) (11, 11)
        assertBool "xxx" $ fromGrid grid (IVec2 0 0) ~== Vec2 0 0
    , testCase "Middle" $ do
        let grid = Grid (Vec2 0 0, Vec2 1 1) (11, 11)
        assertBool "xxx" $ fromGrid grid (IVec2 11 11) ~== Vec2 1 1
    , testCase "End" $ do
        let grid = Grid (Vec2 0 0, Vec2 1 1) (10, 10)
        assertBool "xxx" $ fromGrid grid (IVec2 5 5) ~== Vec2 0.5 0.5
    ]

valueTableTests :: TestTree
valueTableTests = testGroup "Value table creation"
    [ testProperty "Dimension of created table" $
        let gen = do
                iSize <- choose (0, 10)
                jSize <- choose (0, 10)
                let gridRange = (Vec2 0 0, Vec2 1 1)
                pure $ Grid gridRange (iSize, jSize)
        in forAll gen $ \grid@Grid{_numCells = (iSize, jSize)} ->
            let vt = valueTable grid (const ())
            in all (\v -> length v == iSize) vt
               &&
               length vt == jSize
    ]

applyThresholdTests :: TestTree
applyThresholdTests = testGroup "Apply threshold"
    [
    ]

classifyTests :: TestTree
classifyTests = testGroup "Classify"
    [
    ]

contourEdgesTests :: [TestTree] -> TestTree
contourEdgesTests = testGroup "Contour edges"


visualTests :: TestTree
visualTests = testGroup "Visual"
    [ testCase "Circles" $ do
        renderAllFormats 100 100 "out/test" $ do
            setLineWidth 1
            for_ [1..9] $ \r -> do
                let gridDimension = (Vec2 (-10) (-10), Vec2 10 10)
                    cs = contours (Grid gridDimension (100, 100)) (\(Vec2 x y) -> x*x+y*y) (r*r)
                    fitToBox :: (HasBoundingBox geo, Transform geo) => geo -> geo
                    fitToBox = G.transform (G.transformBoundingBox gridDimension (Vec2 (0+10) (0+10), Vec2 (100-10) (100-10)) FitAllMaintainAspect)
                for_ (fitToBox cs) lineSketch
                stroke
    ]
