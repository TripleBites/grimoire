(import merlin/tnn)

(def spec
  (tnn/net :name "mnist-mlp"
    (tnn/input 784 :encode [:threshold 128])
    (tnn/dense 512 :act :ternary)
    (tnn/dense 10  :act :linear)))