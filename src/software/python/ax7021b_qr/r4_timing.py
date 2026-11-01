"""Aggregate histograms only; no frame logs or GUI dependencies."""
import math,time

class TimingStats:
    def __init__(self):
        self.stages = {}

    def add(self, name, milliseconds):
        value = max(0., float(milliseconds))
        stage = self.stages.get(name)
        if stage is None:
            stage = self.stages[name] = [0, 0., float('inf'), 0., [0]*2049]
        stage[0] += 1
        stage[1] += value
        stage[2] = min(stage[2], value)
        stage[3] = max(stage[3], value)
        stage[4][min(2048, int(value))] += 1

    def elapsed(self, name, since_ns):
        value = (time.perf_counter_ns()-since_ns)/1e6
        self.add(name, value)
        return value

    def summary(self):
        result = {}
        for name, (count, total, minimum, maximum, histogram) in self.stages.items():
            def percentile(fraction):
                rank = max(1, math.ceil(count*fraction))
                seen = 0
                for index, n in enumerate(histogram):
                    seen += n
                    if seen >= rank:
                        return dict(lower_ms=index, upper_ms=index+1 if index<2048 else None)
            result[name] = dict(count=count, mean_ms=total/count, min_ms=minimum,
                max_ms=maximum, p50_bin=percentile(.50), p95_bin=percentile(.95))
        return result
