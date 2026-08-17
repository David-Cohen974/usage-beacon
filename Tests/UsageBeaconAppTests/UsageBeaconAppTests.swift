import Foundation
import Testing
@testable import UsageBeaconApp

struct UsageBeaconAppTests {
    @Test
    func globalSettingsDecodesLegacyConfigurationWithNewDefaults() throws {
        let data = Data(
            """
            {
              "showFloatingHUD": true,
              "refreshIntervalMinutes": 15,
              "useCalendarAdjustments": true,
              "selectedCalendarIDs": ["cal-1"]
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(GlobalSettings.self, from: data)

        #expect(settings.refreshIntervalMinutes == 15)
        #expect(settings.workingDaysPerWeek == 5)
        #expect(settings.workingWeekSchedule == .systemDefault)
        #expect(settings.customWorkingWeekdays == [2, 3, 4, 5, 6])
        #expect(settings.selectedCalendarIDs == ["cal-1"])
    }

    @Test
    @MainActor
    func workingDaysPerWeekIgnoresVacationOnNonWorkingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let start = utcDate(year: 2026, month: 8, day: 3)
        let end = utcDate(year: 2026, month: 8, day: 10)
        let blockedDays: Set<Date> = [
            utcDate(year: 2026, month: 8, day: 6),
            utcDate(year: 2026, month: 8, day: 7)
        ]
        var settings = GlobalSettings()
        settings.workingDaysPerWeek = 4

        let remaining = WorkingDayService.remainingWorkingDays(
            from: start,
            until: end,
            blockedDays: blockedDays,
            settings: settings,
            calendar: calendar
        )

        #expect(remaining == 3)
    }

    @Test
    func mondayStartWorkweekUsesMondayThroughFriday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var settings = GlobalSettings()
        settings.workingWeekSchedule = .mondayStart
        settings.workingDaysPerWeek = 5

        let weekdays = WorkingDayService.workingWeekdayNumbers(
            settings: settings,
            referenceDate: utcDate(year: 2026, month: 8, day: 16),
            calendar: calendar
        )

        #expect(weekdays == Set([2, 3, 4, 5, 6]))
    }

    @Test
    func sundayStartWorkweekUsesSundayThroughThursday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var settings = GlobalSettings()
        settings.workingWeekSchedule = .sundayStart
        settings.workingDaysPerWeek = 5

        let weekdays = WorkingDayService.workingWeekdayNumbers(
            settings: settings,
            referenceDate: utcDate(year: 2026, month: 8, day: 16),
            calendar: calendar
        )

        #expect(weekdays == Set([1, 2, 3, 4, 5]))
    }

    @Test
    func customWorkweekUsesOnlySelectedWeekdays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var settings = GlobalSettings()
        settings.workingWeekSchedule = .custom
        settings.customWorkingWeekdays = [1, 2, 4, 5]

        let weekdays = WorkingDayService.workingWeekdayNumbers(
            settings: settings,
            referenceDate: utcDate(year: 2026, month: 8, day: 16),
            calendar: calendar
        )

        #expect(weekdays == Set([1, 2, 4, 5]))
        #expect(settings.effectiveWorkingDaysPerWeek == 4)
    }

    @Test
    func manualBudgetProviderCalculatesRemaining() throws {
        var provider = StoredProvider(kind: .manual, displayName: "Manual")
        provider.manual = ManualBudgetSettings(
            monthlyBudgetUSD: 700,
            spentUSD: 245.50,
            spentTodayUSD: 18.25,
            billingCycleDay: 1,
            lastPromptCostUSD: 1.75
        )

        let snapshot = try ManualBudgetProvider.fetch(
            provider: provider,
            now: Date(timeIntervalSince1970: 1_786_233_600)
        )

        #expect(snapshot.monthlyBudgetUSD == decimal("700"))
        #expect(snapshot.spentUSD == decimal("245.50"))
        #expect(snapshot.remainingUSD == decimal("454.50"))
        #expect(snapshot.spentTodayUSD == decimal("18.25"))
        #expect(snapshot.lastPromptCostUSD == decimal("1.75"))
    }

    @Test
    func cursorAdminProviderParsesSpendAndLastPrompt() async throws {
        var provider = StoredProvider(kind: .cursorAdmin, displayName: "Cursor")
        provider.cursor = CursorAdminSettings(
            apiBaseURL: "https://api.cursor.com",
            accountEmail: "dev@example.com",
            monthlyBudgetOverrideUSD: 0,
            useOverallSpend: true
        )

        let secretStore = InMemorySecretStore()
        try secretStore.saveSecret("crsr_test", account: provider.secretAccount)

        let client = StubHTTPClient { request in
            if request.url?.path == "/teams/spend" {
                return (
                    Data(
                        """
                        {
                          "teamMemberSpend": [
                            {
                              "userId": "user_123",
                              "spendCents": 1250,
                              "overallSpendCents": 21840,
                              "name": "Dev Example",
                              "email": "dev@example.com",
                              "role": "member",
                              "hardLimitOverrideDollars": 0,
                              "monthlyLimitDollars": 700,
                              "effectivePerUserLimitDollars": 700
                            }
                          ],
                          "subscriptionCycleStart": 1785542400000
                        }
                        """.utf8
                    ),
                    response(for: request)
                )
            }

            if request.url?.path == "/teams/filtered-usage-events" {
                return (
                    Data(
                        """
                        {
                          "usageEvents": [
                            {
                              "timestamp": "1786869600000",
                              "chargedCents": 237
                            }
                          ]
                        }
                        """.utf8
                    ),
                    response(for: request)
                )
            }

            Issue.record("Unexpected request path: \(request.url?.path ?? "<nil>")")
            throw ProviderFailure.network("Unexpected request")
        }

        let snapshot = try await CursorAdminProvider.fetch(
            provider: provider,
            secretStore: secretStore,
            httpClient: client,
            now: Date(timeIntervalSince1970: 1_786_869_600)
        )

        #expect(snapshot.monthlyBudgetUSD == decimal("700"))
        #expect(snapshot.spentUSD == decimal("218.40"))
        #expect(snapshot.remainingUSD == decimal("481.60"))
        #expect(snapshot.spentTodayUSD == decimal("2.37"))
        #expect(snapshot.lastPromptCostUSD == decimal("2.37"))
    }

    @Test
    @MainActor
    func cursorPersonalProviderReadsUsageFromLocalHTML() async throws {
        let html = """
        <html>
        <head><title>Cursor Usage</title></head>
        <body>
          <h1>Usage</h1>
          <div>$9.88 / $200 on-demand usage</div>
          <div>+$63.23 free usage</div>
          <div>Resets 2026-09-15</div>
        </body>
        </html>
        """
        let htmlURL = try writeTemporaryHTML(html)

        var provider = StoredProvider(kind: .cursorPersonal, displayName: "Cursor Personal")
        provider.cursorPersonal = CursorPersonalSettings(
            usagePageURL: htmlURL.absoluteString,
            monthlyBudgetOverrideUSD: 0
        )

        let snapshot = try await CursorPersonalProvider.fetch(
            provider: provider,
            now: Date(timeIntervalSince1970: 1_786_233_600)
        )

        #expect(snapshot.monthlyBudgetUSD == decimal("200"))
        #expect(snapshot.spentUSD == decimal("9.88"))
        #expect(snapshot.remainingUSD == decimal("190.12"))
        #expect(DateFormatter.shortDate.string(from: snapshot.billingCycleEnd) == "15 Sep 2026")
    }

    @Test
    func cursorPersonalUsageSummaryMapsIncludedBudget() throws {
        let data = Data(
            """
            {
              "billingCycleStart": "2026-08-01T00:00:00.000Z",
              "billingCycleEnd": "2026-09-01T00:00:00.000Z",
              "membershipType": "enterprise",
              "limitType": "team",
              "isUnlimited": false,
              "individualUsage": {
                "overall": {
                  "enabled": true,
                  "used": 34865,
                  "limit": 70000,
                  "remaining": 35135
                }
              },
              "teamUsage": {
                "onDemand": {
                  "enabled": true,
                  "used": 1210,
                  "limit": null,
                  "remaining": null
                }
              }
            }
            """.utf8
        )
        let summary = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)

        let parsed = try CursorPersonalProvider.mapUsageSummary(
            summary,
            budgetOverrideUSD: nil,
            now: Date(timeIntervalSince1970: 1_786_233_600),
            todaySpentUSD: 0,
            lastPromptCostUSD: decimal("4.491684265136719")
        )

        #expect(parsed.monthlyBudgetUSD == decimal("700"))
        #expect(parsed.spentUSD == decimal("348.65"))
        #expect(parsed.remainingUSD == decimal("351.35"))
        #expect(parsed.spentTodayUSD == 0)
        #expect(parsed.lastPromptCostUSD == decimal("4.491684265136719"))
    }

    @Test
    func cursorPersonalBudgetOverrideUsesConfiguredBudgetCycle() throws {
        let data = Data(
            """
            {
              "billingCycleEnd": "2026-09-16T00:00:00.000Z",
              "individualUsage": {
                "overall": {
                  "enabled": true,
                  "used": 37183,
                  "limit": 70000,
                  "remaining": 32817
                }
              }
            }
            """.utf8
        )
        let summary = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)
        let now = utcDate(year: 2026, month: 8, day: 16)

        let parsed = try CursorPersonalProvider.mapUsageSummary(
            summary,
            budgetOverrideUSD: decimal("700"),
            budgetResetDay: 1,
            now: now
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var settings = GlobalSettings()
        settings.workingDaysPerWeek = 5
        settings.workingWeekSchedule = .sundayStart
        let workingDays = WorkingDayService.remainingWorkingDays(
            from: now,
            until: parsed.billingCycleEnd,
            blockedDays: [],
            settings: settings,
            calendar: calendar
        )
        let perDay = BudgetMath.remainingPerWorkingDay(
            remainingUSD: parsed.remainingUSD,
            workingDaysRemaining: workingDays
        )

        let cycleEndComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: parsed.billingCycleEnd
        )
        #expect(cycleEndComponents.year == 2026)
        #expect(cycleEndComponents.month == 9)
        #expect(cycleEndComponents.day == 1)
        #expect(workingDays == 12)
        #expect(perDay == decimal("27.3475"))
    }

    @Test
    func cursorPersonalDailySpendParserMatchesTodayBucket() {
        let data = Data(
            """
            {
              "data": [
                {
                  "date": "2026-08-15",
                  "spendUSD": 7.25
                },
                {
                  "date": "2026-08-16",
                  "spendUSD": 14.60
                }
              ]
            }
            """.utf8
        )

        let parsed = CursorPersonalProvider.parseTodaySpendResponse(
            data,
            now: utcDate(year: 2026, month: 8, day: 16)
        )

        #expect(parsed == decimal("14.60"))
    }

    @Test
    func cursorPersonalDailySpendParserSumsUsageEvents() {
        let today = utcDate(year: 2026, month: 8, day: 16)
        let data = Data(
            """
            {
              "totalUsageEventsCount": 2,
              "usageEventsDisplay": [
                {
                  "timestamp": "1786838400000",
                  "chargedCents": 125.5
                },
                {
                  "timestamp": "1786842000000",
                  "tokenUsage": { "totalCents": 70 },
                  "cursorTokenFee": 4.5
                }
              ]
            }
            """.utf8
        )

        let parsed = CursorPersonalProvider.parseTodaySpendResponse(data, now: today)
        let pageInfo = CursorPersonalProvider.usageEventPageInfo(data)

        #expect(parsed == decimal("2.00"))
        #expect(pageInfo?.eventCount == 2)
        #expect(pageInfo?.totalEventCount == 2)
    }

    @Test
    func cursorPersonalUsageEventPageRecognizesEmptyToday() {
        let data = Data(
            """
            {
              "totalUsageEventsCount": 0,
              "usageEventsDisplay": []
            }
            """.utf8
        )

        let pageInfo = CursorPersonalProvider.usageEventPageInfo(data)

        #expect(pageInfo?.eventCount == 0)
        #expect(pageInfo?.totalEventCount == 0)
    }

    @Test
    func cursorPersonalUsageEventPageRecognizesEmptyProtobufJSON() {
        let pageInfo = CursorPersonalProvider.usageEventPageInfo(Data("{}".utf8))

        #expect(pageInfo?.eventCount == 0)
        #expect(pageInfo?.totalEventCount == 0)
    }

    @Test
    func cursorPersonalParsesUsageEventScope() {
        let userData = Data(#"{"id":192583298,"sub":"user_example"}"#.utf8)
        let organizationData = Data(
            #"{"organizations":[{"defaultTeamId":6256494,"teams":[{"teamId":6256494}]}]}"#.utf8
        )

        #expect(CursorPersonalProvider.authenticatedUserID(from: userData) == 192_583_298)
        #expect(CursorPersonalProvider.defaultTeamID(from: organizationData) == 6_256_494)
    }

    @Test
    func cursorPersonalLastPromptParserUsesNewestEventCost() {
        let data = Data(
            """
            {
              "usageEventsDisplay": [
                {
                  "timestamp": "1786838400000",
                  "chargedCents": 125.5
                },
                {
                  "timestamp": "1786842000000",
                  "tokenUsage": { "totalCents": 70 },
                  "cursorTokenFee": 4.5
                }
              ]
            }
            """.utf8
        )

        let parsed = CursorPersonalProvider.parseLastPromptCostResponse(data)

        #expect(parsed == decimal("0.745"))
    }

    @Test
    func cursorPersonalUsageParserSupportsCurrentUsageLimitCard() throws {
        let page = CursorDashboardPageSnapshot(
            title: "Usage",
            urlString: "https://cursor.com/dashboard/usage",
            bodyText: """
            Usage
            Monthly spending limit: $50
            Current Usage
            $12.40 of $50 limit
            Resets 2026-09-01
            """,
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )

        let parsed = try CursorPersonalUsageParser.parse(
            page: page,
            now: Date(timeIntervalSince1970: 1_786_233_600),
            budgetOverrideUSD: nil
        )

        #expect(parsed.monthlyBudgetUSD == decimal("50"))
        #expect(parsed.spentUSD == decimal("12.40"))
        #expect(parsed.remainingUSD == decimal("37.60"))
    }

    @Test
    func claudePersonalUsageParserReadsRollingWindowsAndMemberSpend() throws {
        let now = utcDate(year: 2026, month: 8, day: 17)
        let page = ClaudeDashboardPageSnapshot(
            title: "Usage - Claude",
            urlString: "https://claude.ai/settings/usage",
            bodyText: """
            Usage
            Current session
            27% used
            Resets in 2 hrs 30 mins
            Current week
            All models
            63% used
            Resets on Aug 22, 2026 at 12:00 AM
            Extra usage
            $12.50 of $100 monthly spend limit
            """,
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )

        let parsed = try ClaudePersonalUsageParser.parse(
            page: page,
            now: now,
            budgetOverrideUSD: nil
        )

        #expect(parsed.usageWindows.count == 2)
        #expect(parsed.usageWindows[0].kind == .fiveHour)
        #expect(parsed.usageWindows[0].usedPercent == decimal("27"))
        #expect(parsed.usageWindows[0].resetsAt == now.addingTimeInterval(9_000))
        #expect(parsed.usageWindows[1].kind == .sevenDay)
        #expect(parsed.usageWindows[1].usedPercent == decimal("63"))
        #expect(parsed.monthlyBudgetUSD == decimal("100"))
        #expect(parsed.spentUSD == decimal("12.50"))
        #expect(parsed.remainingUSD == decimal("87.50"))
    }

    @Test
    func claudePersonalUsageParserSupportsRateWindowsWithoutDollarSpend() throws {
        let page = ClaudeDashboardPageSnapshot(
            title: "Usage - Claude",
            urlString: "https://claude.ai/settings/usage",
            bodyText: """
            Usage
            5-hour window
            Utilization: 18.5%
            Resets in 45 minutes
            7-day window
            41% utilized
            Resets in 4 days
            """,
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )

        let parsed = try ClaudePersonalUsageParser.parse(
            page: page,
            now: utcDate(year: 2026, month: 8, day: 17),
            budgetOverrideUSD: nil
        )

        #expect(parsed.monthlyBudgetUSD == nil)
        #expect(parsed.remainingUSD == nil)
        #expect(parsed.usageWindows.map(\.usedPercent) == [decimal("18.5"), decimal("41")])
    }

    @Test
    func claudePersonalUsageParserExplainsDisabledMemberAnalytics() {
        let page = ClaudeDashboardPageSnapshot(
            title: "Usage - Claude",
            urlString: "https://claude.ai/settings/usage",
            bodyText: "Member analytics is not enabled. Ask your admin for access.",
            anchorHrefs: [],
            resourceURLs: [],
            nextDataSample: nil
        )

        #expect(throws: ProviderFailure.self) {
            try ClaudePersonalUsageParser.parse(
                page: page,
                now: utcDate(year: 2026, month: 8, day: 17),
                budgetOverrideUSD: nil
            )
        }
    }

    @Test
    func claudePersonalFindsPrivateUsageEndpoint() {
        let page = ClaudeDashboardPageSnapshot(
            title: "New chat - Claude",
            urlString: "https://claude.ai/new#settings/usage",
            bodyText: "Settings",
            anchorHrefs: [],
            resourceURLs: [
                "https://claude.ai/api/organizations/org-test/overage_spend_limit",
                "https://claude.ai/api/organizations/org-test/usage"
            ],
            nextDataSample: nil
        )

        #expect(ClaudePersonalProvider.usageEndpoint(from: page) ==
            "https://claude.ai/api/organizations/org-test/usage")
        #expect(page.looksUsageLike)
    }

    @Test
    func claudePersonalUsageSummaryMapsRollingWindowsAndSpend() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 27.5,
                "resets_at": "2026-08-17T13:00:00.123Z"
              },
              "seven_day": {
                "utilization": 63,
                "resets_at": "2026-08-22T00:00:00Z"
              },
              "spend": {
                "used": { "amount_minor": 1250, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 10000, "currency": "USD", "exponent": 2 },
                "enabled": true
              },
              "member_dashboard_available": true
            }
            """.utf8
        )
        let summary = try JSONDecoder().decode(ClaudePersonalUsageSummaryResponse.self, from: data)

        let parsed = try ClaudePersonalProvider.mapUsageSummary(
            summary,
            budgetOverrideUSD: nil,
            budgetResetDay: 1,
            now: utcDate(year: 2026, month: 8, day: 17)
        )

        #expect(parsed.usageWindows.map(\.usedPercent) == [decimal("27.5"), decimal("63")])
        #expect(parsed.usageWindows[0].resetsAt != nil)
        #expect(parsed.monthlyBudgetUSD == decimal("100"))
        #expect(parsed.spentUSD == decimal("12.50"))
        #expect(parsed.remainingUSD == decimal("87.50"))
    }

    @Test
    func claudePersonalUsageSummarySupportsPureUsageBasedAccount() throws {
        let data = Data(
            """
            {
              "five_hour": null,
              "seven_day": null,
              "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 50000,
                "used_credits": 10638,
                "utilization": 21.276,
                "currency": "USD",
                "decimal_places": 2
              },
              "spend": {
                "used": { "amount_minor": 10638, "currency": "USD", "exponent": 2 },
                "limit": { "amount_minor": 50000, "currency": "USD", "exponent": 2 },
                "percent": 21,
                "enabled": true
              },
              "member_dashboard_available": true
            }
            """.utf8
        )
        let summary = try JSONDecoder().decode(ClaudePersonalUsageSummaryResponse.self, from: data)

        let parsed = try ClaudePersonalProvider.mapUsageSummary(
            summary,
            budgetOverrideUSD: nil,
            budgetResetDay: 1,
            now: utcDate(year: 2026, month: 8, day: 17)
        )

        #expect(parsed.usageWindows.isEmpty)
        #expect(parsed.monthlyBudgetUSD == decimal("500"))
        #expect(parsed.spentUSD == decimal("106.38"))
        #expect(parsed.remainingUSD == decimal("393.62"))
    }

    @Test
    @MainActor
    func claudePersonalProviderReadsUsageFromLocalHTML() async throws {
        let html = """
        <html>
        <head><title>Claude Usage</title></head>
        <body>
          <h1>Usage</h1>
          <div>Current session</div><div>22% used</div><div>Resets in 1 hour</div>
          <div>Current week</div><div>All models</div><div>48% used</div><div>Resets in 3 days</div>
        </body>
        </html>
        """
        let htmlURL = try writeTemporaryHTML(html)

        var provider = StoredProvider(kind: .claudePersonal, displayName: "Claude Personal")
        provider.claudePersonal = ClaudePersonalSettings(usagePageURL: htmlURL.absoluteString)

        let snapshot = try await ClaudePersonalProvider.fetch(
            provider: provider,
            now: utcDate(year: 2026, month: 8, day: 17)
        )

        #expect(snapshot.usageWindows.count == 2)
        #expect(snapshot.usageWindows[0].usedPercent == decimal("22"))
        #expect(snapshot.usageWindows[1].usedPercent == decimal("48"))
        #expect(snapshot.monthlyBudgetUSD == nil)
    }

    @Test
    func anthropicAdminProviderParsesMonthlyCost() async throws {
        var provider = StoredProvider(kind: .anthropicAdmin, displayName: "Claude")
        provider.anthropic = AnthropicAdminSettings(
            apiBaseURL: "https://api.anthropic.com",
            workspaceID: "wrkspc_123",
            monthlyBudgetUSD: 500
        )

        let secretStore = InMemorySecretStore()
        try secretStore.saveSecret("sk-ant-admin-test", account: provider.secretAccount)

        let client = StubHTTPClient { request in
            #expect(request.url?.path == "/v1/organizations/cost_report")
            return (
                Data(
                    """
                    {
                      "data": [
                        {
                          "starting_at": "2026-08-01T00:00:00Z",
                          "ending_at": "2026-08-02T00:00:00Z",
                          "results": [
                            {
                              "amount": "12345",
                              "currency": "USD",
                              "description": "Model Usage",
                              "workspace_id": "wrkspc_123"
                            }
                          ]
                        }
                      ],
                      "has_more": false,
                      "next_page": null
                    }
                    """.utf8
                ),
                response(for: request)
            )
        }

        let snapshot = try await AnthropicAdminProvider.fetch(
            provider: provider,
            secretStore: secretStore,
            httpClient: client,
            now: Date(timeIntervalSince1970: 1_786_233_600)
        )

        #expect(snapshot.monthlyBudgetUSD == decimal("500"))
        #expect(snapshot.spentUSD == decimal("123.45"))
        #expect(snapshot.remainingUSD == decimal("376.55"))
        #expect(snapshot.spentTodayUSD == decimal("123.45"))
    }

    @Test
    func customRESTProviderMapsJsonPaths() async throws {
        var provider = StoredProvider(kind: .customREST, displayName: "REST")
        provider.customREST = CustomRESTSettings(
            endpointURL: "https://example.com/usage",
            httpMethod: "GET",
            headerName: "Authorization",
            headerValuePrefix: "Bearer ",
            monthlyBudgetPath: "limits.monthly",
            spentPath: "usage.month.spent",
            spentTodayPath: "usage.today.spent",
            remainingPath: "",
            resetDatePath: "billing.next_reset_at",
            lastPromptCostPath: "usage.last_prompt",
            dateFormat: "iso8601",
            fallbackBillingCycleDay: 1,
            monthlyBudgetOverrideUSD: 0
        )

        let secretStore = InMemorySecretStore()
        try secretStore.saveSecret("token-123", account: provider.secretAccount)

        let client = StubHTTPClient { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
            return (
                Data(
                    """
                    {
                      "limits": {
                        "monthly": 900
                      },
                      "usage": {
                        "month": {
                          "spent": 350.25
                        },
                        "today": {
                          "spent": 28.40
                        },
                        "last_prompt": 4.15
                      },
                      "billing": {
                        "next_reset_at": "2026-09-01T00:00:00Z"
                      }
                    }
                    """.utf8
                ),
                response(for: request)
            )
        }

        let snapshot = try await CustomRESTProvider.fetch(
            provider: provider,
            secretStore: secretStore,
            httpClient: client,
            now: Date(timeIntervalSince1970: 1_786_233_600)
        )

        #expect(snapshot.monthlyBudgetUSD == decimal("900"))
        #expect(snapshot.spentUSD == decimal("350.25"))
        #expect(snapshot.remainingUSD == decimal("549.75"))
        #expect(snapshot.spentTodayUSD == decimal("28.40"))
        #expect(snapshot.lastPromptCostUSD == decimal("4.15"))
    }
}

private func response(for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

private final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var secrets: [String: String] = [:]

    func loadSecret(account: String) -> String? {
        secrets[account]
    }

    func saveSecret(_ secret: String, account: String) throws {
        secrets[account] = secret
    }

    func deleteSecret(account: String) throws {
        secrets.removeValue(forKey: account)
    }
}

private struct StubHTTPClient: HTTPClientProtocol, Sendable {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private func decimal(_ value: String) -> Decimal {
    Decimal(string: value)!
}

private func writeTemporaryHTML(_ html: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
    let url = directory.appending(path: UUID().uuidString).appendingPathExtension("html")
    try html.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}
