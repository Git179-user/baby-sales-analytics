| ID | TABLE_ID | NAME                   | EXPRESSION                                                                   |   |
|----|----------|------------------------|------------------------------------------------------------------------------|---|
| 79 | 10       | Gross revenue          | SUM('baby_sales sales'[total_sales])                                         |   |
| 80 | 10       | Revenue Last Year      | CALCULATE([Total Revenue], SAMEPERIODLASTYEAR('Date'[Date]))                 |   |
| 81 | 10       | MoM Growth %           | DIVIDE([Total Revenue] - [Revenue Previous Month], [Revenue Previous Month]) |   |
| 82 | 10       | Revenue Previous Month | CALCULATE([Total Revenue], DATEADD('Date'[Date], -1, MONTH))                 |   |
| 83 | 10       | YoY Growth %           | DIVIDE([Total Revenue] - [Revenue Last Year], [Revenue Last Year])           |   |
| 84 | 10       | Total Revenue          | SUM('baby_sales sales'[total_sales])                                         |   |
| 85 | 16       | Avg Order Value        | DIVIDE([Total Revenue], [Total Orders])                                      |   |
| 86 | 16       | Total Orders           | DISTINCTCOUNT('baby_sales sales'[order_id])                                  |   |	