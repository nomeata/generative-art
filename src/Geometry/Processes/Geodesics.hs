module Geometry.Processes.Geodesics (geodesicEquation) where



import Geometry.Core



-- | The geodesic is the shortest path between two points.
--
-- This function allows creating the geodesic differential equation, suitable for
-- using in ODE solvers such as
-- 'Numerics.DifferentialEquation.rungeKuttaAdaptiveStep'.
--
-- The equation is very simple, as long as you don’t have to implement it.
--
-- \[
-- \ddot v^i = \Gamma^i_{kl}\dot v^k\dot v^l \\
-- \Gamma^i_{kl} = \frac12 g^{im} (g_{mk,l}+g_{ml,k}-g_{kl,m}) \\
-- g_{ij}(f) = \left\langle \partial_if,\partial_jf \right\rangle
-- \]
--
-- Go ahead, look at the code, I dare you
geodesicEquation
    :: (Double -> Vec2 -> Double) -- ^ Surface function \(f(t, \mathbf v)\)
    -> Double                     -- ^ Time \(t\)
    -> (Vec2, Vec2)               -- ^ \((\mathbf v, \dot{\mathbf v})\)
    -> (Vec2, Vec2)               -- ^ \((\dot{\mathbf v}, \ddot{\mathbf v})\)
geodesicEquation f t (v, v'@(Vec2 x' y')) =
    ( v'
    , Vec2
        (-c'x__ X X v*x'^2 -2*c'x__ X Y v*x'*y' -c'x__ Y Y v*y'^2)
        (-c'y__ X X v*x'^2 -2*c'y__ X Y v*x'*y' -c'y__ Y Y v*y'^2)
    )
  where
    h = 1e-3

    fdx = d X h (f t)
    fdy = d Y h (f t)

    fdxV = fdx v
    fdyV = fdy v

    -- Metric g_{ab}
    g__ X X p = 1 + fdx p^2
    g__ X Y p = fdx p * fdy p
    g__ Y X p = g__ X Y p
    g__ Y Y p = 1 + fdy p^2

    -- Inverse metric g^{ab}
    (g'x'x, g'x'y, g'y'x, g'y'y) =
        let denominator = (1+fdxV^2+fdyV^2)
        in ( (1+fdyV^2)   /denominator
           , -(fdxV*fdyV) /denominator
           , g'x'y
           , (1+fdxV^2)   /denominator
        )

    -- Derivative of the metric g_{ab,c}
    g__d_ X X X = g_x_xd_x
    g__d_ X X Y = g_x_xd_y
    g__d_ X Y X = g_x_yd_x
    g__d_ X Y Y = g_x_yd_y
    g__d_ Y X X = g_y_xd_x
    g__d_ Y X Y = g_y_xd_y
    g__d_ Y Y X = g_y_yd_x
    g__d_ Y Y Y = g_y_yd_y

    g_x_xd_x = d X h (g__ X X)
    g_x_xd_y = d Y h (g__ X X)
    g_x_yd_x = d X h (g__ X Y)
    g_x_yd_y = d Y h (g__ X Y)
    g_y_xd_x = d X h (g__ Y X)
    g_y_xd_y = d Y h (g__ Y X)
    g_y_yd_x = d X h (g__ Y Y)
    g_y_yd_y = d Y h (g__ Y Y)

    -- Christoffel symbols, \Gamma^i_{kl} = \frac12 g^{im} (g_{mk,l}+g_{ml,k}-g_{kl,m})
    c'x__ k l p = 0.5 * (g'x'x * (g__d_ X k l p + g__d_ X l k p - g__d_ k l X p) + g'x'y * (g__d_ Y k l p + g__d_ Y l k p - g__d_ k l Y p))
    c'y__ k l p = 0.5 * (g'y'x * (g__d_ X k l p + g__d_ X l k p - g__d_ k l X p) + g'y'y * (g__d_ Y k l p + g__d_ Y l k p - g__d_ k l Y p))

-- | Spatial derivative
d :: VectorSpace v => Dim -> Double -> (Vec2 -> v) -> Vec2 -> v
d X h f v = (f (v +. Vec2 h 0) -. f v) /. h
d Y h f v = (f (v +. Vec2 0 h) -. f v) /. h

data Dim = X | Y
