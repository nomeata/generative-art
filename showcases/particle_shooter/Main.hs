module Main (main) where

import           Control.Monad
import           Control.Monad.ST
import           Control.Parallel.Strategies
import           Data.Foldable
import qualified Data.Vector                     as V
import           Data.Word
import           Graphics.Rendering.Cairo        as C
import qualified System.Random.MWC               as Random
import qualified System.Random.MWC.Distributions as Random

import Draw
import Geometry                      as G
import Numerics.DifferentialEquation
import Numerics.VectorAnalysis

main :: IO ()
main = do
    let systemResult = runST (systemSetup systemConfig)
    let (w, h) = boundingBoxSize (_boundingBox systemConfig)
    withSurfaceAuto
        "showcases/particle_shooter.png"
        (round w)
        (round h)
        (\surface -> C.renderWith surface (render systemResult))

data SystemConfig s = SystemConfig
    { _seed :: V.Vector Word32

    , _boundingBox :: BoundingBox

    , _numHills :: Int
    , _hillLocation :: Random.Gen s -> ST s Vec2
    , _hillCharge :: Random.GenST s -> ST s Double

    , _numParticles  :: Int
    , _particleMass :: Double
    , _particleCharge :: Random.GenST s -> ST s Double
    }

systemConfig :: SystemConfig s
systemConfig = SystemConfig
    { _seed = V.fromList [113,5,9,1,39,45]

    , _boundingBox =
        let lo = Vec2 0 0
            hi = Vec2 2560 1440
            bb = boundingBox (lo, hi)
            center = G.transform (G.inverse (G.translate (boundingBoxCenter bb)))
        in center bb

    , _numHills = 5000
    , _hillLocation = \gen -> gaussianVec2 (Vec2 0 0) 1500 gen
    , _hillCharge = \_gen -> pure 1

    , _numParticles  = 10000
    , _particleMass = 1
    , _particleCharge = \_gen -> pure 1
    }

data SystemResult = SystemResult
    { _trajectories :: [([Vec2], (Vec2, Vec2))]
    , _coulombWells :: [(Vec2, Double)]
    }

initializeGen
    :: SystemConfig s
    -> ST s (Random.Gen s)
initializeGen SystemConfig{..} = do
    gen <- Random.initialize _seed
    _ <- fmap (\x -> const "Warm up the generator" (x::[Int]))
              (replicateM 10000 (Random.uniform gen))
    pure gen

systemSetup :: SystemConfig s -> ST s SystemResult
systemSetup config@SystemConfig{..} = do
    gen <- initializeGen config

    (potential, coulombWells) <- potentials config gen

    particles <- do
        let mkParticle = do
                let x0 = Vec2 0 0
                a <- Random.uniformRM (0, 360) gen
                let v0 = polar (deg a) 1
                q <- _particleCharge gen
                pure ((x0, v0), q)
        replicateM _numParticles mkParticle

    let odeSolutions =
            [ (rungeKuttaAdaptiveStep ode ic t0 dt0 toleranceNorm tolerance, ic)
            | (ic, charge) <- particles
            , let ode _t (x,v) = (v, charge *. negateV (grad potential x) /. _particleMass)
            , let t0 = 0
            , let dt0 = 1
            , let tolerance = 1e-2
            , let toleranceNorm (x,v) = sqrt (max (normSquare x) (normSquare v))
            ]

    let trajectoryThunks = flip map odeSolutions $ \(odeSolution, ic) ->
            let getTrajectory sol = [x | (_t, (x, _v)) <- sol]
                timeCutoff = takeWhile (\(t, _) -> t < 3000)
                spaceCutoff = takeWhile (\(_t, (x, _v)) -> overlappingBoundingBoxes x _boundingBox)
                simplify = simplifyTrajectory 1
            in ((simplify . getTrajectory . timeCutoff . spaceCutoff) odeSolution, ic)
        !trajectoriesNF = trajectoryThunks `using` parListChunk 64 rdeepseq

    pure SystemResult
        { _trajectories = trajectoriesNF
        , _coulombWells = coulombWells
        }

render :: SystemResult -> Render ()
render SystemResult{..} = do
    do let BoundingBox (Vec2 x y) _ = _boundingBox systemConfig
       C.translate (-x) (-y)
    cairoScope $ do
        setSourceRGB 1 1 1
        paint

    setLineWidth 1
    for_ _coulombWells $ \(center, charge) -> cairoScope $ do
            setColor $ mmaColor 0 1
            for_ [1,3..10] $ \r -> do
                setColor $ mmaColor 0 (1/r**0.9)
                circleSketch center (8*(r*abs charge)**(1/2.5))
                stroke

    for_ (zip [1..] _trajectories) $ \(i, (trajectory, _ic)) -> do
        when (mod i 100 == 1) (liftIO (putStrLn ("Paint trajectory " ++ show i ++ "/" ++ show (length _trajectories))))
        cairoScope $ do
            setColor $ mmaColor 3 0.03
            pathSketch trajectory
            stroke
        pure ()

gaussianVec2
    :: Vec2 -- ^ Mean
    -> Double -- ^ Standard deviation
    -> Random.GenST s
    -> ST s Vec2
gaussianVec2 (Vec2 muX muY) sigma gen = Vec2 <$> Random.normal muX sigma gen <*> Random.normal muY sigma gen

potentials
    :: SystemConfig s
    -> Random.Gen s
    -> ST s (Vec2 -> Double, [(Vec2, Double)])
potentials SystemConfig{..} gen = do
    hills <- do
        hills' <- replicateM _numHills $ do
            center <- _hillLocation gen
            charge <- _hillCharge gen
            pure (center, charge)
        let removeOutliers = filter (\(center, _) -> overlappingBoundingBoxes center (G.transform (G.scale 1.1) _boundingBox))
                           . filter (\(center, _) -> norm center > 70)
        pure (removeOutliers hills')
    pure (\p -> sum' [coulombPotential center charge p | (center, charge) <- hills]
         , hills
         )

coulombPotential
    :: Vec2   -- ^ Center
    -> Double -- ^ Charge
    -> Vec2   -- ^ Particle location
    -> Double -- ^ Magnitude of the potential
coulombPotential center charge p = charge / norm (p -. center)

sum' :: [Double] -> Double
sum' = foldl' (+) 0