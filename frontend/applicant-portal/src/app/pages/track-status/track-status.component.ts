import { NgIf } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { Subscription, interval } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { ApplicationsService, LoanApplication } from '../../services/applications.service';

@Component({
  selector: 'app-track-status',
  standalone: true,
  imports: [NgIf],
  template: `
    <div class="page" *ngIf="application">
      <h1>Application status</h1>
      <p>Status: <span class="status-badge">{{ application.status }}</span></p>
      <p *ngIf="application.riskScore !== null">Risk score: {{ application.riskScore }}</p>
      <p>Submitted: {{ application.submittedAt }}</p>
      <button *ngIf="application.status === 'Draft'" (click)="submit()">Submit application</button>
    </div>
  `,
})
export class TrackStatusComponent implements OnInit, OnDestroy {
  application: LoanApplication | null = null;
  private applicationId = '';
  private pollSubscription?: Subscription;

  constructor(
    private readonly route: ActivatedRoute,
    private readonly applications: ApplicationsService,
  ) {}

  ngOnInit(): void {
    this.applicationId = this.route.snapshot.paramMap.get('id') ?? '';

    // Simple polling for the skeleton; a fuller build would subscribe to a WebSocket/SSE
    // channel fed by the Application Status Projector worker's read model.
    this.pollSubscription = interval(5000)
      .pipe(switchMap(() => this.applications.getApplication(this.applicationId)))
      .subscribe((app) => (this.application = app));

    this.applications.getApplication(this.applicationId).subscribe((app) => (this.application = app));
  }

  ngOnDestroy(): void {
    this.pollSubscription?.unsubscribe();
  }

  submit(): void {
    this.applications.submitApplication(this.applicationId).subscribe(() => {
      this.applications.getApplication(this.applicationId).subscribe((app) => (this.application = app));
    });
  }
}
