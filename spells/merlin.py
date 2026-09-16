# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "jax",
# ]
# ///

# Ref:
# https://github.com/jax-ml/jax

import jax
import jax.numpy as jnp
from jax import random

def predict(params, inputs):
  for W, b in params:
    outputs = jnp.dot(inputs, W) + b
    inputs = jnp.tanh(outputs)  # inputs to the next layer
  return outputs                # no activation on last layer

def loss(params, inputs, targets):
  preds = predict(params, inputs)
  return jnp.sum((preds - targets)**2)

if __name__ == '__main__':
    print("Starting Merlin")
    grad_loss = jax.jit(jax.grad(loss))  # compiled gradient evaluation function
    perex_grads = jax.jit(jax.vmap(grad_loss, in_axes=(None, 0, 0)))  # fast per-example grads
