(import ../nets/mnist-mlp :as arch)

(def net   (tnn/build arch/spec {:seed 42}))
(def train (mnist/load "data/mnist" :train))
(def test  (mnist/load "data/mnist" :test))
(def opt   (top/new net {:gamma 1e-3 :tau 1e-6}))

(for epoch 0 10
  (top/train-epoch opt train {:batch 64})
  (printf "epoch %d  test acc %.4f" epoch (tnn/evaluate net test)))

(tnn/save net "ckpt/mnist-mlp.tnn.janet")