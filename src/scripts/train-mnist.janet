# The experiment (SPEC section 8): train a ternary MLP on MNIST with Top.
# Runs from milestone M4 on; save needs M5.
(import grimoire/tnn)
(import ../nets/mnist-mlp :as arch)

(def train (mnist/load "data/mnist/train-images-idx3-ubyte" "data/mnist/train-labels-idx1-ubyte"))
(def test  (mnist/load "data/mnist/t10k-images-idx3-ubyte"  "data/mnist/t10k-labels-idx1-ubyte"))
(def net   (tnn/build arch/spec 42))
(def opt   (top/new net {:gamma 1e-3 :tau [1e-5 1e-4] :batch 64}))

(for epoch 0 10
  (loop [first :range [0 (mnist/count train) 6400]]
    (def r (top/train opt train first 6400))
    (printf "  %5d  loss %.4f  acc %.4f  flips %j" first (r :loss) (r :acc) (r :flips)))
  (printf "epoch %d  test acc %.4f  layer0 %j"
          epoch (tnn/evaluate net test) (tnn/stats net 0)))

(tnn/save net "ckpt/mnist-mlp.tnn.janet")
