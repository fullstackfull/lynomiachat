# Reads several stores at once (Customer 360, order search): the block runs for each item in at most `concurrency`
# threads, and the results come back in item order after at most `timeout` seconds, nil for items still running. The
# block handles its own errors. Threads hold no database connection while waiting on a store (Rails returns it after
# each query).
module Commerce::Parallel
  def self.map(items, concurrency:, timeout:, &)
    results = {}
    lock = Mutex.new
    queue = Queue.new
    items.each_with_index { |item, index| queue << [item, index] }
    queue.close
    wait(Array.new([concurrency, items.size].min) { worker(queue, results, lock, &) }, timeout)
    lock.synchronize { Array.new(items.size) { |index| results[index] } }
  end

  def self.worker(queue, results, lock)
    Thread.new do
      Rails.application.executor.wrap do
        while (pair = queue.pop)
          result = yield pair.first
          lock.synchronize { results[pair.last] = result }
        end
      end
    end
  end

  def self.wait(workers, timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
      workers.each { |worker| worker.join([deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max) }
    end
  end

  private_class_method :worker, :wait
end
