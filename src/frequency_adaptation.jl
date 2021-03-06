# A FrequencyAdapter adapts the frequencies with which a set of
# values/strategies/methods should be applied/tried in an optimization problem.
# It is based on the Adaptive Coordinate Frequencies scheme described in:
#
# T. Glasmachers and U. Dogan, "Accelerated Coordinate Descent with
# Adaptive Coordinate Frequencies", 2013.
#
# but generalized so that it can support more than the adaptation of only
# the coordinates in a Coordinate Descent scheme. The things that are being
# adapted are identified by integers in 1:n, with n being the main parameter.
type FrequencyAdapter
  n::Int                # number of methods to select from
  eta::Float64          # 0..1, running average decay rate
  c::Float64            # positive, sensitivity to progress changes
  pmin::Float64         # minimal method probability
  pmax::Float64         # maximal method probability

  p::Vector{Float64}    # Current method weights
  psum::Float64         # Sum of p[i]
  a::Vector{Float64}    # Number of pending method applications
  deltahat::Float64     # Running average of the progress values.

  block::Vector{Int}    # current queue of methods to apply
  block_pos::Int		# current position in the queue

  numupdates::Int     # Number of times we have been updated.
  min_updates::Int    # Number of updates until we start adapting frequencies.

  FrequencyAdapter(n; c = 0.2, eta = 1/n, pmin = 0.05, pmax = 20.0) = begin
    new(n, eta, c, pmin, pmax,
      fill(1/n, n), 1.0,
      zeros(Float64, n),
      0.0,
      shuffle!(collect(1:n)), 1,
      0, n)
  end
end

frequencies(fa::FrequencyAdapter) = weights(fa.p)

# Return the index of the next method that should be used. The base
# FrequencyAdapter first creates a block of randomly shuffled methods that should
# be applied and then selected the next one from it. If there is a current
# block which is non-empty, use that, if not create a new block. However,
# the first block is always random shuffles of all the methods since we need
# to learn about their effectiveness.
function next(fa::FrequencyAdapter)
  if fa.block_pos > length(fa.block)
    fill_block!(fa)
  end
  #println("Taking $(fa.block_pos) from block = ", fa.block)
  fa.block_pos += 1
  return fa.block[fa.block_pos-1]
end

# Fill the block of methods to apply
function fill_block!(fa::FrequencyAdapter)
  #print("Creating new block, psum = $(fa.psum), a = ", fa.a, ", p = ", fa.p)
  empty!(fa.block)
  # fill the block according to the fa.p and fa.a
  last_pos = 0 # position in the block
  for(i in 1:fa.n)
    fa.a[i] += (fa.n * fa.p[i] / fa.psum)
    if fa.a[i] >= 1.0
      # block should have at least one i-th method
      num_ai = floor(Int, fa.a[i])
      @assert num_ai > 0
      fa.a[i] -= num_ai # adjust the remainder
      new_pos = last_pos+num_ai
      resize!(fa.block, new_pos)
      fa.block[(last_pos+1):(new_pos)] = i
      last_pos = new_pos
    end
  end
  # Due to rounding errors the block is sometimes empty so we select the one
  # with largest a value.
  if last_pos == 0
    #println("Empty block created. Rectifying., std(p) = ", std(fa.p))
    #print("psum = $(fa.psum), a = ", fa.a, ", p = ", fa.p)
    i = indmax(fa.a)
    fa.a[i] = 0
    resize!(fa.block, 1)
    fa.block[1] = i
  end
  #println("Created new block = ", block)
  fa.block_pos = 1
  shuffle!(fa.block)
end

# Update the internal model of progress and success rate of each method based
# on the latest progress value of one method. Progress values should be larger
# the larger the progress/improvement was.
function update!(fa::FrequencyAdapter, methodIndex, progress)
  # If we already have collected a few samples of progress rates we can update
  # the pi. This is the common case.
  if fa.numupdates >= fa.min_updates
    pnew = fa.deltahat > 0 ? clamp(fa.p[methodIndex] * exp(fa.c * (progress / fa.deltahat - 1)),
                 fa.pmin, fa.pmax) : fa.pmin
    #print("i = ", methodIndex, ", pi = ", fa.p[methodIndex], ", pnew = ", pnew, ", psum = ", fa.psum)
    fa.psum += (pnew - fa.p[methodIndex])
    fa.p[methodIndex] = pnew
    #print(", new psum = ", fa.psum, ", deltahat = ", fa.deltahat)
    fa.deltahat = (1 - fa.eta) * fa.deltahat + fa.eta * progress
    #println(", new deltahat = ", fa.deltahat)
  else
    # Until we have collected at least min_updates we just sum the progress
    # values so we can later calculate their average.
    fa.deltahat += progress
  end
  fa.numupdates += 1
  if fa.numupdates == fa.min_updates
    #print("Setting deltahat, was = ", fa.deltahat, " (min_updates = $(fa.min_updates))")
    fa.deltahat = fa.deltahat / fa.min_updates
    #println(", now = ", fa.deltahat)
  end
end
