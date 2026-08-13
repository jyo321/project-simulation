import { DecimalPipe, NgFor, NgIf } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';
import { DecisioningService, ReviewerQueueItem } from '../../services/decisioning.service';

@Component({
  selector: 'app-queue',
  standalone: true,
  imports: [NgFor, NgIf, RouterLink, DecimalPipe],
  template: `
    <div class="page">
      <h1>Reviewer queue</h1>
      <table>
        <thead>
          <tr>
            <th>Applicant</th>
            <th>Amount</th>
            <th>Status</th>
            <th>Risk score</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr *ngFor="let item of queue">
            <td>{{ item.applicantName }}</td>
            <td>{{ item.requestedAmount | number: '1.0-0' }}</td>
            <td>
              {{ item.status }}
              <span class="badge-fraud" *ngIf="item.fraudFlagged">⚠ fraud flagged</span>
            </td>
            <td>{{ item.riskScore ?? 'pending' }}</td>
            <td><a [routerLink]="['/applications', item.loanApplicationId, 'review']">Review</a></td>
          </tr>
        </tbody>
      </table>
    </div>
  `,
})
export class QueueComponent implements OnInit {
  queue: ReviewerQueueItem[] = [];

  constructor(private readonly decisioning: DecisioningService) {}

  ngOnInit(): void {
    this.decisioning.getQueue().subscribe((items) => (this.queue = items));
  }
}
