import { DecimalPipe, NgFor, NgIf } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';
import { DecisioningService, ReviewerQueueItem } from '../../services/decisioning.service';

@Component({
  selector: 'app-queue',
  standalone: true,
  imports: [NgFor, NgIf, RouterLink, DecimalPipe],
  template: `
    <div class="page page-wide">
      <div class="page-header">
        <h1>Reviewer queue</h1>
        <p class="page-subtitle">{{ queue.length }} application{{ queue.length === 1 ? '' : 's' }} awaiting review.</p>
      </div>

      <table *ngIf="queue.length">
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
              <span class="status-badge" [class]="'status-' + item.status.toLowerCase()">{{ item.status }}</span>
              <span class="badge-fraud" *ngIf="item.fraudFlagged">⚠ Fraud flagged</span>
            </td>
            <td>{{ item.riskScore ?? 'Pending' }}</td>
            <td><a class="btn-link" [routerLink]="['/applications', item.loanApplicationId, 'review']">Review →</a></td>
          </tr>
        </tbody>
      </table>

      <div class="empty-state" *ngIf="!queue.length">Nothing waiting on you right now.</div>
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
