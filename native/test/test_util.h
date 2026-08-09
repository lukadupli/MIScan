#pragma once

#include <cmath>
#include <cstdio>
#include <exception>
#include <string>
#include <vector>

// Minimal zero-dependency test harness.
//
// TEST(name) { ... } declares and registers a case. The CHECK_* macros record a
// failure and keep going, so one run reports every broken invariant instead of
// stopping at the first. runAll() prints a summary and returns a process exit code.

namespace testing {

	struct TestCase {
		const char* name;
		void (*fn)();
	};

	inline std::vector<TestCase>& registry() {
		static std::vector<TestCase> cases;
		return cases;
	}

	inline int& failuresInCurrentTest() {
		static int count = 0;
		return count;
	}

	struct Registrar {
		Registrar(const char* name, void (*fn)()) { registry().push_back({ name, fn }); }
	};

	inline void reportFailure(const char* file, int line, const std::string& message) {
		failuresInCurrentTest()++;
		printf("    FAIL %s:%d\n         %s\n", file, line, message.c_str());
	}

	inline std::string describeNear(const char* expr, double got, double want, double tolerance) {
		char buf[512];
		snprintf(buf, sizeof(buf), "%s = %.6g, expected %.6g (tolerance %.6g, off by %.6g)",
			expr, got, want, tolerance, std::fabs(got - want));
		return buf;
	}

	inline int runAll() {
		int failedTests = 0;
		for (const auto& test : registry()) {
			printf("  %s\n", test.name);
			failuresInCurrentTest() = 0;
			try {
				test.fn();
			}
			catch (const std::exception& e) {
				reportFailure("<exception>", 0, std::string("threw std::exception: ") + e.what());
			}
			catch (...) {
				// BasicLinearException does not derive from std::exception
				reportFailure("<exception>", 0, "threw an unexpected exception");
			}
			if (failuresInCurrentTest()) failedTests++;
		}

		int total = (int)registry().size();
		printf("\n%s: %d/%d tests passed\n", failedTests ? "FAILED" : "PASSED", total - failedTests, total);
		return failedTests ? 1 : 0;
	}

} // namespace testing

#define TEST(name)                                                        \
	static void name();                                                   \
	static testing::Registrar name##_registrar(#name, name);              \
	static void name()

#define CHECK(condition)                                                  \
	do {                                                                  \
		if (!(condition)) testing::reportFailure(__FILE__, __LINE__, "CHECK(" #condition ") is false"); \
	} while (0)

#define CHECK_MSG(condition, message)                                     \
	do {                                                                  \
		if (!(condition)) testing::reportFailure(__FILE__, __LINE__, (message)); \
	} while (0)

// absolute tolerance
#define CHECK_NEAR(got, want, tolerance)                                  \
	do {                                                                  \
		double _g = (got), _w = (want), _t = (tolerance);                 \
		if (!(std::fabs(_g - _w) <= _t))                                  \
			testing::reportFailure(__FILE__, __LINE__, testing::describeNear(#got, _g, _w, _t)); \
	} while (0)

// tolerance relative to the expected value
#define CHECK_NEAR_REL(got, want, relativeTolerance)                      \
	do {                                                                  \
		double _g = (got), _w = (want), _t = std::fabs((relativeTolerance) * _w); \
		if (!(std::fabs(_g - _w) <= _t))                                  \
			testing::reportFailure(__FILE__, __LINE__, testing::describeNear(#got, _g, _w, _t)); \
	} while (0)
