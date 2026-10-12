# The MNIST network spec (SPEC section 8). The last layer is the linear
# output; every other layer is ternary with activation threshold :theta.

(def spec
  {:input 784
   :layers [{:out 512 :theta 0.5}
            {:out 10}]})
